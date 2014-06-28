library(plyr)

## useful inside reorder(), to invert the resulting factor levels
neglength <- function(x) -1 * length(x)

games <- c("2014-04-12_vanNH-at-pdxST", "2014-04-20_sfoDF-at-vanNH",
           "2014-04-26_vanNH-at-seaRM", "2014-05-10_seaRM-at-vanNH",
           "2014-05-17_vanNH-at-sfoDF", "2014-05-24_pdxST-at-vanNH",
           "2014-05-31_vanNH-at-seaRM", "2014-06-07_seaRM-at-vanNH",
           "2014-06-15_pdxST-at-vanNH", "2014-06-21_vanNH-at-sfoDF",
           "2014-04-12_seaRM-at-sfoDF", "2014-04-19_sfoDF-at-seaRM",
           "2014-04-26_pdxST-at-sfoDF")
game_file <- file.path("..", "games", games, "07_resolvedGame",
                       paste0(games, "_gameplay-resolved.tsv"))
names(game_file) <- games
game_play <-
  ldply(game_file, function(gg) read.delim(gg, stringsAsFactor = FALSE),
        .id = "game")
str(game_play) # 8016 obs. of  8 variables

## function to create numbered possessions
## feed it raw poss_team (as a vector) or a matrix/data.fram with poss_team and
## point and optionally game (latter seems a very rare special case)
determine_possession <- function(x) {
  if(is.vector(x)) {
    n <- length(x)
    is_start <- c(TRUE, !(x[2:n] == x[seq_len(n - 1)]))
  } else {
    n <- nrow(x)
    if(is.null(x$game)) {
      is_start <-
        c(TRUE, !(x[2:n, 'poss_team'] == x[seq_len(n - 1), 'poss_team'] &
                    x[2:n, 'point'] == x[seq_len(n - 1), 'point']))
    } else {
      is_start <-
        c(TRUE, !(x[2:n, 'poss_team'] == x[seq_len(n - 1), 'poss_team'] &
                    x[2:n, 'point'] == x[seq_len(n - 1), 'point'] &
                    x[2:n, 'game'] == x[seq_len(n - 1), 'game']))
    }    
    return(cumsum(is_start))
  }
}

## create variables that denote possessions

## Why would I ever need an absolute possession variable for the entire season?
## I made this possible in case I ever analyze groups of points from different
## games where two "point 9"'s could end up adjacent to each other
# mutate(game_play,
#       poss_abs = determine_possession(game_play[c('poss_team', 'point', 'game')]))

## absolute possession variable within game
game_play <- ddply(game_play, ~ game, function(x)
  mutate(x, poss_abs = determine_possession(x[c('poss_team', 'point')])))
str(game_play) # 8016 obs. of  9 variables

## relative possession variable, i.e. within point
game_play <- ddply(game_play, ~ point + game, function(x)
  data.frame(x,
             poss_rel = determine_possession(x[c('poss_team', 'point')])))
str(game_play) # 8016 obs. of  10 variables:

## get the pulling team, which is a point-level thing
game_play <- ddply(game_play, ~ game + point, function(x) {
  data.frame(x, pull_team = x$pl_team[1])
})
str(game_play) # 8016 obs. of  11 variables:

## reorder factor levels for pull_team, convert poss_team to factor
## 2014-06: this is based on western conference rankings
jTeams <- c("pdxST", "vanNH", "seaRM", "sfoDF")
jFun <- function(x, xlevels = jTeams) factor(x, levels = xlevels)
game_play <- transform(game_play, pull_team = jFun(pull_team),
                       poss_team = factor(poss_team, levels = jTeams))
str(game_play)

vars_how_i_want <- c('game', 'period', 'point', 'pull_team',
                     'poss_abs', 'poss_rel', 'event',
                     'poss_team', 'pl_team', 'pl_pnum', 'pl_code')
game_play <- game_play[vars_how_i_want]

out_dir <- file.path("..", "games", "2014_west")
if(!file.exists(out_dir)) dir.create(out_dir)

out_file <- file.path(out_dir, "2014_west_gameplay.rds")
saveRDS(game_play, out_file)
message("wrote ", out_file)

out_file <- file.path(out_dir, "2014_west_gameplay.tsv")
write.table(game_play, out_file, quote = FALSE, sep = "\t", row.names = FALSE)
message("wrote ", out_file)

out_file <- file.path(out_dir, "2014_west_gameplay.dput")
dput(game_play, out_file)
message("wrote ", out_file)

## now aggregate at the level of a possession  

## how poss_dat differs from game_play, other than aggregation:
## n_events = number of events
## score = logical indicating if possession ends with a goal
## scor_team = who scored ... NA if nobody did
## who = o_line vs. d_line
poss_dat <- ddply(game_play, ~ game + poss_abs, function(x) {
  score <- which(grepl("L*G", x$pl_code))
  ## get rid of any rows after a goal. why? becasue of cases like point 35 of
  ## 2014-04-12_vanNH-at-pdxST, in which a defensive foul is recorded after a
  ## successful goal; the goal was not being picked up here as the final event
  ## of the possession and was, instead, being recorded as an *offensive* foul
  if(length(score) > 0)
    x <- x[seq_len(score), ]
  ## if possession ends with a *defensive* foul, remove the final row; examples:
  ## 2014-04-26_vanNH-at-seaRM poss_abs 23, 2014-05-17_vanNH-at-sfoDF poss_abs 
  ## 92, 2014-05-31_vanNH-at-seaRM poss_abs 57; all have possessions in which a 
  ## thrower has the disc, there's a foul by the defense and ... the throw is 
  ## not caught ... we need to see the offensive throwaway as the last event of
  ## the possession, not the defensive foul
  n <- nrow(x)
  if(x$pl_team[n] != x$poss_team[n] & x$pl_code[n] == 'F') {
    x <- x[seq_len(n - 1), ]
    n <- nrow(x)
  }
  pull_team <- x$pull_team[1]
  n <- nrow(x)
  huck <- grepl("L", x$pl_code)
  scor_team <- as.character(if(any(score)) x$pl_team[max(score)] else NA)
  who <- ifelse(x$poss_team[n] == pull_team, "d_line", "o_line")
  if(x$pl_code[n] == 'F' & x$pl_team[n] == x$poss_team[n]) {
    x$pl_code[n] <- if(who == 'o_line') "off F" else "TA"
  }
  data.frame(x[n, ], n_events = n, huck = any(huck),
             score = any(score), scor_team, who)
})
str(poss_dat) # 1268 obs. of  16 variables:

## sanity checks of poss_dat
(tmp <- ddply(poss_dat, ~ game,
              function(x) with(subset(x, score), table(scor_team))))
## yes agrees with actual final scores
colSums(subset(tmp, select = -game))
addmargins(with(poss_dat, table(who, score)))

## reorder factor levels for scor_team
jTeams <- c("pdxST", "vanNH", "seaRM", "sfoDF")
jFun <- function(x, xlevels = jTeams) factor(x, levels = xlevels)
poss_dat <- transform(poss_dat , scor_team = jFun(scor_team))
str(poss_dat)

## if possession ends due to end of period, set pl_code to 'eop'
poss_dat <- ddply(poss_dat, ~ game + point, function(x) {
  n <- nrow(x)
  if(!x$score[n]) x$pl_code[n] <- 'eop'
  return(x)
})

## clean-up

## revalue pl_code in poss_dat, then reorder by frequency 
## i.e. if possession ends in a throwaway, make code reflect that better
poss_dat$pl_code <-
  mapvalues(poss_dat$pl_code, # revalue() won't work due to factor level ''
            from = c(  '', 'PU',  'L'),
            to   = c('TA', 'TA', 'TA'))
poss_dat$pl_code <- with(poss_dat, reorder(pl_code, pl_code, neglength))
as.data.frame(table(poss_dat$pl_code, dnn = "a_code"))

## create a new version of the pl_code that is coarser: a_code
poss_dat$a_code <-
  mapvalues(poss_dat$pl_code,
            from = c('D', 'HB', 'FB', 'G', 'LG'),
            to   = c('D',  'D',  'D', 'G',  'G'))
poss_dat$a_code <- with(poss_dat, reorder(a_code, a_code, neglength))
as.data.frame(table(poss_dat$a_code, dnn = "a_code"))

## create a new version of the a_code that is YET coarser: b_code
poss_dat$b_code <-
  mapvalues(poss_dat$a_code,
            from = c(    'D',   'TA',    'TD',   'VTT',   'VST', 'off F'),
            to   = c('def +','off -', 'off -', 'off -', 'off -', 'off -'))
poss_dat$b_code <- with(poss_dat, reorder(b_code, b_code, neglength))
as.data.frame(table(poss_dat$b_code, dnn = "b_code"))

out_file <- file.path(out_dir, "2014_west_possessions.rds")
saveRDS(poss_dat, out_file)
message("wrote ", out_file)

out_file <- file.path(out_dir, "2014_west_possessions.tsv")
write.table(poss_dat, out_file, quote = FALSE, sep = "\t", row.names = FALSE)
message("wrote ", out_file)

out_file <- file.path(out_dir, "2014_west_possessions.dput")
dput(poss_dat, out_file)
message("wrote ", out_file)

## now aggregate at the level of a point  

## how point_dat differs from poss_dat, other than aggregation:
## n_events = number of events in the point (comes from poss_dat$event!)
point_dat <- ddply(poss_dat, ~ game + point, function(x) {
  n <- nrow(x)
  x$n_events <- NULL
  x <- rename(x, c("event" = "n_events", "poss_rel" = "n_poss"))
  x[n, ]
})
str(point_dat)         # 552 obs. of 17 variables
table(point_dat$score, useNA = "always")   # 503 TRUE       49 FALSE
table(point_dat$pl_code, useNA = "always") # 396 G  107 LG  49 eop
table(point_dat$a_code, useNA = "always")  # 503 G          49 eop
table(point_dat$b_code, useNA = "always")  # 503 G          49 eop
table(point_dat$huck, useNA = "always")    # 352 FALSE 200 TRUE
addmargins(with(point_dat, table(score, huck)))
#         huck
# score   FALSE TRUE Sum
#   FALSE    45    4  49
#   TRUE    307  196 503
#   Sum     352  200 552

out_file <- file.path(out_dir, "2014_west_points.rds")
saveRDS(point_dat, out_file)
message("wrote ", out_file)

out_file <- file.path(out_dir, "2014_west_points.tsv")
write.table(point_dat, out_file, quote = FALSE, sep = "\t", row.names = FALSE)
message("wrote ", out_file)

out_file <- file.path(out_dir, "2014_west_points.dput")
dput(point_dat, out_file)
message("wrote ", out_file)
