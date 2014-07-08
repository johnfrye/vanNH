library(plyr)
library(stringr) # str_extract()

## I predict this function will be moved to a file of helper functions and,
## ultimately, into a helper package
replace_NA_with_empty_string <- function(x) {x[is.na(x)] <- ""; return(x)}

## when run in batch mode, provide game identifier on command line
options <- commandArgs(trailingOnly = TRUE)

if(length(options) < 1) {
  #game <- "2014-04-12_vanNH-at-pdxST"
  #game <- "2014-04-20_sfoDF-at-vanNH"
  #game <- "2014-04-26_vanNH-at-seaRM"
  #game <- "2014-05-10_seaRM-at-vanNH"
  #game <- "2014-05-17_vanNH-at-sfoDF"
  #game <- "2014-05-24_pdxST-at-vanNH"
  #game <- "2014-05-31_vanNH-at-seaRM"
  #game <- "2014-06-07_seaRM-at-vanNH"
  #game <- "2014-04-26_pdxST-at-sfoDF"
  game <- "2014-06-28_vanNH-at-pdxST"
} else {
  game <- options[1]
}

## parse the game identifier
tmp <- strsplit(game, split = "_")[[1]]
game_date <- tmp[1]
tmp <- strsplit(tmp[2], split = "-")[[1]]
away_team <- tmp[1]
home_team <- tmp[3]
jTeams <- sort(c(away_team, home_team))

game_dir <- file.path("..", "games", game, "03_concatGoogleExtract")

in_file <- file.path(game_dir, paste0(game, "_gameplay-raw.tsv"))
game_play <- read.delim(in_file, stringsAsFactors = FALSE)
#str(game_play)
message(game, ":\n  ", nrow(game_play), " rows of raw game play found")

## Offense and Defense are misleading variable names. Rename to suggest they
## record actions by the "receiving" and "pulling" teams, respectively.
game_play <-
  rename(game_play, c("Offense" = "recv_raw", "Defense" = "pull_raw"))

## replace NAs in game_play$recv_raw and game_play$pull_raw with ""
game_play <-
  transform(game_play,
            recv_raw = replace_NA_with_empty_string(recv_raw),
            pull_raw = replace_NA_with_empty_string(pull_raw))

## eliminate trailing game play rows for which recv_raw == pull_raw == ''
nBefore <- nrow(game_play)
jFun <- function(z) {
  n <- nrow(z)
  offset_index <- c(2:n, n) # get entry from row below; last element: get self
  z <- mutate(z, both = paste0(recv_raw, pull_raw),
              bothOffset = both[offset_index],
              is_empty = both == bothOffset & both == '')
  return(subset(z, !is_empty, select = c(point, recv_raw, pull_raw))  )
}
game_play <- ddply(game_play, ~ point, jFun)
nAfter <- nrow(game_play)
nDiff <- nBefore - nAfter
if(nDiff != 0) {
  message("  ", nDiff, " out of ", nBefore,
          " rows eliminated; game play cells were empty")
}

## remove leading single quote from recv_raw and pull_raw, if present
## I have seen this happen for seaRM player 00
## seems to arise from the "extract data from Google spreadsheet" step
jFun <- function(x) gsub("'","", x)
game_play <-
  transform(game_play, recv_raw = jFun(recv_raw), pull_raw = jFun(pull_raw))

## game play data should be empty, start with a ?, start with a digit, or be
## [TO|to]
jFun <- function(x) {
  x == "" | grepl("^[\\?\\d]", x, perl = TRUE) |
    grepl("TO", x, ignore.case = TRUE)
}
code_seems_valid <- colwise(jFun)(game_play[c('pull_raw', 'recv_raw')])
weird_code <- !apply(code_seems_valid, 1, all)
if(any(weird_code)) {
  message("  these rows have game play that's not empty, not a TO, yet doesn't start with a digit")
  game_play[weird_code, ]
}
  
## separate raw game play into a number and a code
## e.g. 81D into 81 and D
## but accomodate ? as the "number"
get_number_part <- function(x) {
  ret_val <- str_extract(x, perl("^[\\?\\d]+"))
  ret_val <- replace_NA_with_empty_string(ret_val)
  return(ret_val)
}
get_letter_part <- function(x) {
  ret_val <- str_extract(x, perl("[a-zA-Z]+$"))
  ret_val <- replace_NA_with_empty_string(ret_val)
  return(ret_val)
}
game_play <- transform(game_play,
                       recv_pnum = I(get_number_part(recv_raw)),
                       recv_code = I(get_letter_part(recv_raw)),
                       pull_pnum = I(get_number_part(pull_raw)),
                       pull_code = I(get_letter_part(pull_raw)))

## make sure all codes are upper case
game_play <- transform(game_play,
                       recv_code = toupper(recv_code),
                       pull_code = toupper(pull_code))

## function to find double game play rows
find_double_game_plays <-
  function(z) with(z, which( (pull_pnum != '' | pull_code != '') & 
                              (recv_pnum != "" | recv_code != '') ) )

## identify rows with game play recorded for both teams
fix_me <- find_double_game_plays(game_play)
message("  found ", length(fix_me),
        " rows with game play recorded for both teams")
#game_play[fix_me, ]

## split double game play rows into two separate rows
## the only tricky thing is deciding the order
## big picture: try to keep the O play first, D play second
jFun <- function(x) {
  offense_codes <- c('', 'PU', 'L', 'G', 'LG', 'TO', 'LTO')
  foul_codes <- c('F', 'VP')
  sub_codes <- c('SO', 'SI')
  fix_me <- find_double_game_plays(x)
  needs_fix <- length(fix_me) > 0
  while(needs_fix) {
    fix_this <- fix_me[1]
    codes <- c(recv_code = x[fix_this, "recv_code"],
               pull_code = x[fix_this, "pull_code"])
    
    ## most common situation: one code is from offense_codes, other from
    ## foul_codes
    if(all(codes %in% offense_codes == !(codes %in% foul_codes))) {
      if(names(codes)[codes %in% offense_codes] == "recv_code") {
        jOrder <- c("recv", "pull")
        ## this erroneous data once produced a warning message here:
        ##     point event pull_raw pull_pnum pull_code recv_raw recv_pnum recv_code
        ## 213    13    12      17      17              2pu       2       PU
        ## I corrected the data and did not delve into the code.
      } else {
        jOrder <- c("pull", "recv")
      }
    } else { # just pick an order
      jOrder <- c("pull", "recv")
      if(!all(grepl("S[OI]+", codes))) {
        message(paste("Row", fix_this, "of point", x$point[1],
                      "indicates events for both teams\n, but it's a novel code",
                      "combination. LOOK AT THIS DATA!"))
        print(x[fix_this + (-1:1), ])
      }      
    }
    
    ## duplicate the affected row
    x <- x[rep(1:nrow(x), ifelse(1:nrow(x) %in% fix_this, 2, 1)), ]
    ## 'empty' out raw, num, and code for either recv or pull
    x[fix_this, paste0(jOrder[2], c('_raw', '_pnum', '_code'))] <- ''
    x[fix_this + 1, paste0(jOrder[1], c('_raw', '_pnum', '_code'))] <- ''
        
    ## update the to do list
    fix_me <- find_double_game_plays(x)
    needs_fix <- length(fix_me) > 0
  } 
  x$event <- 1:nrow(x)
  return(x)
}
game_play <- ddply(game_play, ~ point, jFun)

## do any double game play rows remain?
fix_me <- find_double_game_plays(game_play)
if(length(fix_me) > 0) {
  message("double game play rows we are not prepared to address and that remain")
  game_play[fix_me, ]
} else {
  message("  no double game play rows remain")
}

## drop recv_raw, pull_raw
game_play <- subset(game_play, select = -c(recv_raw, pull_raw))

## rearrange the variables
the_vars <-
  c('point', 'event', 'pull_pnum', 'pull_code', 'recv_pnum', 'recv_code')
game_play <- game_play[the_vars]

message("  ", nrow(game_play), " rows of clean game play will be written\n")

out_dir <- file.path("..", "games", game, "05_cleanedGame")
if(!file.exists(out_dir)) dir.create(out_dir)

out_file <- file.path(out_dir, paste0(game, "_gameplay-clean.tsv"))
write.table(game_play, out_file, quote = FALSE, sep = "\t", row.names = FALSE)
#message("wrote ", out_file)
