## ----setup, include=FALSE------------------------------------------------
source("global_config.R")

## ps ax | grep "mysql"

## mysql -u root -p

## CREATE DATABASE abdwr;

## ----src_mysql_hide, echo=FALSE------------------------------------------
library(RMySQL)
conn <- dbConnect(MySQL(), dbname = "abdwr", 
                  default.file = "~/.my.cnf")

## ----src_mysql_show, eval=FALSE------------------------------------------
## library(RMySQL)
## conn <- dbConnect(MySQL(), dbname = "abdwr",
##                   user = "bbaumer", password = "password")

## ------------------------------------------------------------------------
class(conn)

## ----load_gamelog--------------------------------------------------------
load_gamelog <- function(season) {
  glheaders <- read.csv("data/game_log_header.csv")
  remote <- paste0("http://www.retrosheet.org/gamelogs/gl", 
                   season, ".zip")
  local <- paste0("gl", season, ".zip")
  download.file(url = remote, destfile = local)
  unzip(local)
  local_txt <- gsub(".zip", ".txt", local) %>%
    toupper()
  gamelog <- read_csv(local_txt, 
                      col_names = names(glheaders),
                      na = character())
  file.remove(local)
  file.remove(local_txt)
  return(gamelog)
}

## ----gl2012--------------------------------------------------------------
gl2012 <- load_gamelog(2012)

## ----load_season, results='hide'-----------------------------------------
dbWriteTable(conn, name = "gamelogs", value = gl2012, 
             append = TRUE, row.names = FALSE)

## ----append_game_logs----------------------------------------------------
append_game_logs <- function(conn, season) {
  message(paste("Working on", season, "season..."))
  one_season <- load_gamelog(season)
  dbWriteTable(conn, name = "gamelogs", value = one_season, 
               append = TRUE, row.names = FALSE)
}

## ----include=FALSE-------------------------------------------------------
dbSendQuery(conn, "TRUNCATE TABLE gamelogs;")

## ----lapply_load, results='hide', message=FALSE--------------------------
map(1995:2017, append_game_logs, conn = conn)

## ----query---------------------------------------------------------------
query <- "
SELECT date, hometeam, dayofweek, attendance
FROM gamelogs
WHERE date > 20060101
  AND hometeam IN ('CHN', 'CHA');
"
chi_attendance <- dbGetQuery(conn, query) 
head(chi_attendance)

## ------------------------------------------------------------------------
library(lubridate)
chi_attendance <- chi_attendance %>%
  mutate(the_date = ymd(date),
         attendance = ifelse(attendance == 0, NA, attendance))

## ----chiAttendance, warning=FALSE, fig.cap="Comparison of attendance by day of the week on games played at home by the Cubs (\\cmd{CHN)} and the White Sox (\\cmd{CHA})."----
ggplot(chi_attendance, 
       aes(x = wday(the_date), y = attendance, 
           color = hometeam)) +
  geom_jitter(height = 0, width = 0.2, alpha = 0.2) + 
  geom_smooth() + 
  scale_y_continuous("Attendance") + 
  scale_x_continuous("Day of the Week", breaks = 1:7, 
                     labels = wday(1:7, label = TRUE)) + 
  scale_color_manual(values = c(crcblue, "gray70"))

## ----rockies_games-------------------------------------------------------
query <- "
SELECT date, parkid, visitingteam, hometeam, 
  visitorrunsscored AS awR, homerunsscore AS hmR
FROM gamelogs
WHERE (hometeam = 'COL' OR visitingteam = 'COL') 
  AND Date > 19950000;
"
rockies_games <- dbGetQuery(conn, query)

## ----rockies_runs--------------------------------------------------------
rockies_games <- rockies_games %>%
  mutate(runs = awR + hmR, 
         coors = parkid == "DEN02")

## ----coors, fig.cap="Comparison of runs scored by the Rockies and their opponents at Coors Field and in other ballparks."----
ggplot(rockies_games, 
       aes(x = year(ymd(date)), y = runs, linetype = coors)) +
  stat_summary(fun.data = "mean_cl_boot") + 
  xlab("Season") +
  ylab("Runs per game (both teams combined)") +
  scale_linetype_discrete(name = "Location", 
                          labels = c("Other", "Coors Field"))

## mysql -u username -p password lahman < lahman2016.sql

## ----retro---------------------------------------------------------------
library(retro)
db <- src_mysql_cnf("retrosheet")
retro <- etl("retro", db = db, dir = "~/dumps/retro/")

## ----retro_populate, eval=FALSE------------------------------------------
## retro %>%
##   etl_init() %>%
##   etl_update(season = 1990:1999)

## ----eval=FALSE, include=FALSE-------------------------------------------
## # add partitions
## dbRunScript(retro$con,
##             system.file("sql", "optimize.mysql", package = "retro"))

## ----hrPF, warning=FALSE-------------------------------------------------
query <- "
SELECT away_team_id, home_team_id, event_cd
FROM events
WHERE year_id = 1996
  AND event_cd IN (2, 18, 19, 20, 21, 22, 23);
"
hr_PF <- dbGetQuery(retro$con, query)

## ----event_fl------------------------------------------------------------
hr_PF <- hr_PF %>%
  mutate(was_hr = ifelse(event_cd == 23, 1, 0))

## ----ev_away-------------------------------------------------------------
ev_away <- hr_PF %>%
  group_by(team_id = away_team_id) %>%
  summarize(hr_event = mean(was_hr)) %>%
  mutate(type = "away")

ev_home <- hr_PF %>%
  group_by(team_id = home_team_id) %>%
  summarize(hr_event = mean(was_hr)) %>%
  mutate(type = "home")

## ----ev_compare----------------------------------------------------------
ev_compare <- ev_away %>%
  bind_rows(ev_home) %>%
  spread(key = type, value = hr_event)
  
ev_compare

## ----park_factors--------------------------------------------------------
ev_compare <- ev_compare %>%
  mutate(pf = 100 * home / away)
ev_compare %>%
  arrange(desc(pf)) %>%
  head()
ev_compare %>%
  arrange(pf) %>%
  head()

## ----andres, warning=FALSE-----------------------------------------------
query <- "
SELECT away_team_id, home_team_id, event_cd
FROM events
WHERE year_id = 1996
  AND event_cd IN (2, 18, 19, 20, 21, 22, 23)
  AND bat_id = 'galaa001';
"
andres <- dbGetQuery(retro$con, query) %>%
  mutate(was_hr = ifelse(event_cd == 23, 1, 0))

## ----andres_pf-----------------------------------------------------------
andres_pf <- andres %>%
  inner_join(ev_compare, by = c("home_team_id" = "team_id")) %>%
  summarize(mean_pf = mean(pf))
andres_pf

## ----andres_correction---------------------------------------------------
47 / (andres_pf / 100)

