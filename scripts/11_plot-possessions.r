library(plyr)
library(ggplot2)

jWidth <- 5
jHeight <- 4

games <- c("2014-04-12_vanNH-at-pdxST", "2014-04-20_sfoDF-at-vanNH",
           "2014-04-26_vanNH-at-seaRM", "2014-05-10_seaRM-at-vanNH",
           "2014-05-17_vanNH-at-sfoDF", "2014-05-24_pdxST-at-vanNH",
           "2014-05-31_vanNH-at-seaRM", "2014-06-07_seaRM-at-vanNH",
           "2014-06-15_pdxST-at-vanNH")
game_file <- file.path("..", "games", games, "07_resolvedGame",
                       paste0(games, "_gameplay-resolved.tsv"))
names(game_file) <- games
gpDat <-
  ldply(game_file, function(gg) read.delim(gg, stringsAsFactor = FALSE),
        .id = "game")
str(gpDat) # 5664 obs. of  8 variables

## function to create numbered possessions
## feed it raw poss_team (as a vector) or a matrix/data.fram with poss_team and
## point and optionally game
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
# mutate(gpDat,
#       poss_abs = determine_possession(gpDat[c('poss_team', 'point', 'game')]))

## absolute possession variable within game
gpDat <- ddply(gpDat, ~ game, function(x)
  mutate(x, poss_abs = determine_possession(x[c('poss_team', 'point')])))
str(gpDat) # 5664 obs. of  9 variables

## relative possession variable, i.e. within point
gpDat <- ddply(gpDat, ~ point + game, function(x)
  data.frame(x,
             poss_rel = determine_possession(x[c('poss_team', 'point')])))
str(gpDat) # 5664 obs. of  10 variables:

## get the pulling team, which is a point-level thing
gpDat <- ddply(gpDat, ~ game + point, function(x) {
  data.frame(x, pull_team = x$pl_team[1])
})
str(gpDat) # 5664 obs. of  11 variables:

## aggregate to possessions: to gpDat variables, adds logical indicating if
## possession ends in a point, scoring team
poss_dat <- ddply(gpDat, ~ game + poss_abs, function(x) {
  pull_team <- x$pull_team[1]
  n <- nrow(x)
  score <- which(grepl("L*G", x$pl_code))
  scor_team <- as.character(if(any(score)) x$pl_team[max(score)] else NA)
  who <- ifelse(x$poss_team[n] == pull_team, "d_line", "o_line")
  if(x$pl_code[n] == 'F') {
    x$pl_code[n] <- if(who == 'o_line') "off F" else "TA"
  }
  data.frame(x[n, ], score = any(score), scor_team, who)
})
str(poss_dat) # 842 obs. of  14 variables:

## sanity checks of poss_dat
ddply(poss_dat, ~ game + scor_team, summarize, score = sum(score))
## yes agrees with actual final scores
addmargins(with(poss_dat, table(who, score)))
# score
# who      FALSE TRUE Sum
#   o_line   313  236 549
#   d_line   167  126 293
#   Sum      480  362 842

table(ddply(poss_dat, ~ game + point,
            summarize, n_pull_tms = length(unique(pull_team))))


## reorder and revalue pl_code in poss_dat
poss_dat$pl_code <-
  mapvalues(poss_dat$pl_code, # revalue() won't work due to factor level ''
            from = c(  '', 'PU',  'L'),
            to   = c('TA', 'TA', 'TA'))
poss_dat$pl_code <- with(poss_dat, reorder(pl_code, pl_code, length))
as.data.frame(table(poss_dat$pl_code, dnn = "a_code"))

## create a new version of the pl_code that is coarser: a_code
poss_dat$a_code <-
  mapvalues(poss_dat$pl_code,
            from = c('D', 'HB', 'FB', 'G', 'LG'),
            to   = c('D',  'D',  'D', 'G',  'G'))
poss_dat$a_code <- with(poss_dat, reorder(a_code, a_code, length))
as.data.frame(table(poss_dat$a_code, dnn = "a_code"))

## create a new version of the a_code that is YET coarser: b_code
poss_dat$b_code <-
  mapvalues(poss_dat$a_code,
            from = c(    'D',   'TA',    'TD',   'VTT',   'VST', 'off F'),
            to   = c('def +','off -', 'off -', 'off -', 'off -', 'off -'))
poss_dat$b_code <- with(poss_dat, reorder(b_code, b_code, length))
as.data.frame(table(poss_dat$b_code, dnn = "b_code"))

## function that counts how often a code occurs, computes a proportion, and also
## a "pretty" proportion suitable for putting on a figure
count_em_up <- function(code_var, x = poss_dat) {
  code_freq <- as.data.frame(table(x[[code_var]], dnn = code_var))
  row_to_append <- setNames(data.frame("Sum", sum(code_freq$Freq)),
                            c(code_var, "Freq"))
  code_freq <- rbind(code_freq, row_to_append)
  code_freq <-
    mutate(code_freq, prop = Freq / Freq[nrow(code_freq)],
           pretty_prop = as.character(round(prop, 2)))
  return(code_freq)
}

## function that assembles the common part of the "how possessions end?" series
## of barcharts
construct_basic_barchart <- function(code_freq, code_var, fill_var = NULL) {
  non_sum_rows <- code_freq[[code_var]] != "Sum"
  if(is.null(fill_var)) {
    p <- ggplot(subset(code_freq, non_sum_rows),
                aes_string(x = code_var, y = "prop")) +
      geom_bar(stat = "identity")
  } else {
    p <- ggplot(subset(code_freq, non_sum_rows),
                aes_string(x = code_var, y = "prop", fill = fill_var)) +
      geom_bar(stat = "identity", position = "dodge")
  }
  p + xlab("how possessions end") + ylab("proportion of possessions")
}

## how do possessions end? using very coarse b_code
last_code_freq <- count_em_up("b_code")
p <- construct_basic_barchart(last_code_freq, "b_code")
p + geom_text(aes(label = pretty_prop), vjust = -0.2, size = 4)
ggsave("../web/figs/barchart_how_possessions_end_coarse.png",
       width = jWidth, height = jHeight)

## how do possessions end? using b_code AND O line vs D line
last_code_freq_by_line <-
  ddply(poss_dat, ~ who, function(x) count_em_up("b_code", x))
p <- construct_basic_barchart(last_code_freq_by_line, "b_code", "who")
p + geom_text(aes(label = pretty_prop), vjust = -0.2, size = 4,
              position = position_dodge(0.9)) + 
  labs(fill = "who's on offense?")
ggsave("../web/figs/barchart_how_possessions_end_coarse_by_line.png",
       width = jWidth, height = jHeight)

## how do possessions end? split out by poss_team
last_code_freq_by_team <-
  ddply(poss_dat, ~ poss_team, function(x) count_em_up("b_code", x))
p <- construct_basic_barchart(last_code_freq_by_team, "b_code")
p + facet_wrap(~ poss_team) + ylim(0, 0.54) +
  geom_text(aes(label = pretty_prop), vjust = -0.2, size = 4)
ggsave("../web/figs/barchart_how_possessions_end_coarse_by_team.png",
       width = jWidth, height = jHeight)

## how do possessions end? using b_code AND O line vs D line AND poss_team
last_code_freq_by_line_and_team <-
  ddply(poss_dat, ~ poss_team + who, function(x) count_em_up("b_code", x))
p <- construct_basic_barchart(last_code_freq_by_line_and_team, "b_code", "who")
p + facet_wrap(~ poss_team) + 
  geom_text(aes(label = pretty_prop), vjust = -0.2, size = 2,
            position = position_dodge(0.9)) + 
  labs(fill = "who's on offense?") + ylim(0, 0.6)
ggsave("../web/figs/barchart_how_possessions_end_coarse_by_line_and_team.png",
       width = jWidth, height = jHeight)

## how do possessions end? using a_code
last_code_freq <- count_em_up("a_code")
p <- construct_basic_barchart(last_code_freq, "a_code")
p + geom_text(aes(label = pretty_prop), vjust = -0.2, size = 4)
ggsave("../web/figs/barchart_how_possessions_end_detailed.png",
       width = jWidth, height = jHeight)

## how do possessions end? using a_code AND O line vs D line
last_code_freq_by_line <-
  ddply(poss_dat, ~ who, function(x) count_em_up("a_code", x))
p <- construct_basic_barchart(last_code_freq_by_line, "a_code", "who")
p + geom_text(aes(label = pretty_prop), vjust = -0.2, size = 2,
              position = position_dodge(0.9)) + 
  labs(fill = "who's on offense?")
ggsave("../web/figs/barchart_how_possessions_end_detailed_by_line.png",
       width = jWidth, height = jHeight)

## how do possessions end? split out by poss_team
last_code_freq_by_team <-
  ddply(poss_dat, ~ poss_team, function(x) count_em_up("a_code", x))
p <- construct_basic_barchart(last_code_freq_by_team, "a_code")
p + facet_wrap(~ poss_team) + ylim(0, 0.54) +
  geom_text(aes(label = pretty_prop), vjust = -0.2, size = 4)
ggsave("../web/figs/barchart_how_possessions_end_detailed_by_team.png")

## how do possessions end? split out by o_line vs d_line and team
last_code_freq_by_line_and_team <-
  ddply(poss_dat, ~ poss_team + who, function(x) count_em_up("a_code", x))
p <- construct_basic_barchart(last_code_freq_by_line_and_team, "a_code", "who")
p + facet_wrap(~ poss_team) + 
  geom_text(aes(label = pretty_prop), vjust = -0.2, size = 2,
            position = position_dodge(0.9)) + 
  labs(fill = "who's on offense?") + ylim(0, 0.6)
ggsave("../web/figs/barchart_how_possessions_end_detailed_by_line_and_team.png")

## when team x receives a pull, how often do they score vs turn it over?
j_team <- "vanNH"
str(x <- subset(poss_dat, pull_team != j_team)) # 393 obs
with(x, table(poss_rel, score, scor_team))
str(x <- subset(poss_dat, pull_team != j_team & scor_team == j_team)) # 119 obs.

str(x <- subset(gpDat, game == "2014-06-15_pdxST-at-vanNH" & point == 6))
str(y <- subset(poss_dat, game == "2014-06-15_pdxST-at-vanNH" & point == 6))

## aggregate to points: record how many possessions, who scored (if anyone),
## and whether it was a hold or break
jFun <- function(x) {
  n <- nrow(x)
  pull_team <- x$pl_team[1]
  ## careful to accomodate a foul on the goal catch and to persist even if there
  ## are somehow two codes containing G (alert will be raised elsewhere; this is
  ## neither the time nor the place to clean a game)
  its_a_goal <- which(grepl("L*G", x$pl_code))
  if(length(its_a_goal) > 0) {
    goal_row <- max(its_a_goal)
    scor_team <- x$pl_team[goal_row]
    status <- ifelse(pull_team == scor_team, "break", "hold")
  } else {
    scor_team <- status <- NA
  }
  y <- with(x[n, ], data.frame(period, point, pull_team,
                               scor_team, status, n_poss = max(poss_rel)))
  return(y)
}
poss_dat <- ddply(gpDat, ~ point + game, jFun)
str(poss_dat) # 394 obs. of  7 variables:

## get rid of points that end with no goal
poss_dat <- subset(poss_dat, !is.na(status))
str(poss_dat) # 362 obs. of  7 variables:

## distribution of possession length
poss_freq <- ddply(poss_dat, ~ n_poss, summarize,
                   n = length(point), prop = length(point) / nrow(poss_dat))
poss_freq <-
  mutate(poss_freq,
         status = factor(ifelse((poss_freq$n_poss %% 2) == 1,
                                "hold", "break"),
                         levels = c('hold', 'break')),
         pretty_prop = ifelse(prop > 0.01, as.character(round(prop, 2)), ''),
         cum_prop = cumsum(prop),
         pretty_cum_prop = ifelse(cum_prop < 0.98,
                                  as.character(round(cum_prop, 2)), ''))
poss_freq
str(poss_freq)

p <- ggplot(poss_freq, aes(x = n_poss, y = prop, fill = status))
p + geom_bar(stat = "identity") +
  geom_text(aes(label = pretty_prop), vjust = -0.2, size = 4) +
  scale_x_discrete(breaks = 1:17) +
  ylab("proportion of points scored after exactly x possessions") +
  xlab("x = number of possessions before point ends in a goal") +
  theme(legend.position = c(1, 1), legend.justification = c(1, 1),
        legend.background = element_rect(fill = 0)) + labs(fill = "")
ggsave("../web/figs/poss_n_dist_by_status.png")

p <- ggplot(poss_freq, aes(x = n_poss, y = cum_prop))
p + geom_bar(stat = "identity") + 
  geom_text(aes(label = pretty_cum_prop), vjust = -0.2, size = 4) +
  scale_x_discrete(breaks = 1:17) + 
  ylab("proportion of points scored in x possessions or less") +
  xlab("x = number of possessions before point ends in a goal")
ggsave("../web/figs/poss_n_CDF_by_status.png")


## now retain info separately for break and hold points
poss_freq <- ddply(poss_dat, ~ status + n_poss, summarize,
                   n = length(point), abs_prop = n / nrow(poss_dat))
poss_freq
str(poss_freq)
poss_freq <- ddply(poss_freq, ~ status, mutate, wi_prop = n / sum(n))
p <- ggplot(poss_freq, aes(x = n_poss, y = n))
p + geom_bar(stat = "identity") + facet_grid(. ~ status) + 
  scale_x_discrete(breaks = 1:17) +
  ylab("number of points scored after exactly x possessions") +
  xlab("x = number of possessions before point ends in a goal")

p <- ggplot(poss_freq, aes(x = n_poss, y = wi_prop))
p + geom_bar(stat = "identity") + facet_grid(. ~ status) + 
  scale_x_discrete(breaks = 1:17) +
  ylab("number of points scored after exactly x possessions") +
  xlab("x = number of possessions before point ends in a goal")

p <- ggplot(poss_freq, aes(x = n_poss, y = abs_prop, fill = status))
p + geom_bar(stat = "identity") + 
  scale_x_discrete(breaks = 1:17) +
  ylab("proportion of points scored after exactly x possessions") +
  xlab("x = number of possessions before point ends in a goal")

## now retain status AND scor_team
poss_freq <- ddply(poss_dat, ~ scor_team + status + n_poss, summarize,
                   n = length(point))
poss_freq
str(poss_freq)
poss_freq <- ddply(poss_freq, ~ scor_team, mutate, team_prop = n / sum(n))
poss_freq
str(poss_freq)
aggregate(team_prop ~ scor_team, poss_freq, sum)

p <- ggplot(poss_freq, aes(x = n_poss, y = team_prop, fill = status))
p + geom_bar(stat = "identity") + 
  scale_y_continuous(breaks = (1:5)/10) + 
  scale_x_continuous(breaks = 1:17, limits = c(0, 13)) + 
  facet_wrap(~ scor_team) + 
  ylab("proportion of points scored after exactly x possessions") +
  xlab("x = number of possessions before point ends in a goal") +
  theme(legend.position = c(1, 1), legend.justification = c(1, 1),
        legend.background = element_rect(fill = 0)) + labs(fill = "")
ggsave("../web/figs/poss_n_dist_by_scor_team_and_status.png")


## NOT IN USE
## for viewing rows in gpDat where something happens, e.g. a possession ends
## with a specific code
# d_ply(poss_dat, ~ pl_code, function(x) {
#   match_vars <- c('game', 'period', 'point', 'event')
#   gp_rows <-
#     join(x[match_vars],
#          data.frame(gpDat[match_vars], row = seq_len(nrow(gpDat))))$row
#   display_vars <- c('game', 'point', 'event', 'poss_team', 'pl_team',
#                     'pl_pnum', 'pl_code')
#   for(i in seq_along(gp_rows)) {
#     print(gpDat[gp_rows[i] + (-2:2), display_vars])
#     cat("\n")
#   }
#   
# })

