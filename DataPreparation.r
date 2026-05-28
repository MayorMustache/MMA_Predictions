# =============================================================================
# Data Preperation - Feature Engineering 
# =============================================================================
# Description: This script calculates additional variables and paritioning the 
#              data into train, test and validation. 
# Author:      Michael Schenk
# Dataset:     UFC Data by https://www.kaggle.com/datasets/neelagiriaditya/ufc-datasets-1994-2025
# =============================================================================

# --- 1. Setup and packages ----------------------------------------------------

# Change the System Language
Sys.setLanguage("en")

# Clear the workspace 
rm(list = ls())

# Load the needed packages
pacman::p_load(dplyr, tidyr, RKaggle, lubridate, forcats)

# Load the dataset from Kaggle
KaggleData <- RKaggle::get_dataset("neelagiriaditya/ufc-datasets-1994-2025")

# --- 2. Self defined functions ------------------------------------------------

# Define a custome cumsum function that can handle NAs
custome_cumsum <- function(values){
  
  values = tidyr::replace_na(values, 0)
  
  return(cumsum(values))
  
}


# --- 3. Calculate Variables that can change every fight------------------------

ChangingVariables <- KaggleData[[4]] %>% 
  
  # Select the relevant column
  dplyr::select(event_id, date, fight_id, r_id, b_id, winner_id, method) %>% 
  
  # Transform to long data, since we are currently not interested if the fighter 
  # is red or blue
  tidyr::pivot_longer(cols = c(r_id, b_id), names_to = "corner", values_to = "fighter_id") %>% 

  # Create helper columns that check for win, loss, etc.
  # Info: - Here other stands for draws/NC or other
  #       - ko includes ko and tko
  dplyr::mutate(helper_match_win_all = ifelse(test = winner_id == fighter_id, yes = 1, no = 0),
                helper_match_win_sub = ifelse(test = (winner_id == fighter_id & method == "Submission"), yes = 1, no = 0),
                helper_match_win_ko = ifelse(test = (winner_id == fighter_id & grepl("TKO", method)), yes = 1, no = 0),
                helper_match_win_decision = ifelse(test = (winner_id == fighter_id & grepl("Decision", method)), yes = 1, no = 0),
                helper_match_loss_all = 1 - helper_match_win_all,
                helper_match_loss_sub = ifelse(test = (winner_id != fighter_id & method == "Submission"), yes = 1, no = 0),
                helper_match_loss_ko = ifelse(test = (winner_id != fighter_id & grepl("TKO", method)), yes = 1, no = 0),
                helper_match_loss_decision = ifelse(test = (winner_id != fighter_id & grepl("Decision", method)), yes = 1, no = 0),
                helper_match_other = as.numeric(is.na(helper_match_win_all))) %>% 
  
  dplyr::arrange(date) %>% 
  
  dplyr::group_by(fighter_id) %>% 
  
  # Calculate the records. Drop the first entry, since we need a delay
  dplyr::mutate(rec_wins_all = c(0, head(custome_cumsum(helper_match_win_all), n = -1)),
                rec_wins_sub = c(0, head(custome_cumsum(helper_match_win_sub), n = -1)),
                rec_wins_ko = c(0, head(custome_cumsum(helper_match_win_ko), n = -1)),
                rec_wins_decision = c(0, head(custome_cumsum(helper_match_win_decision), n = -1)),
                rec_loss_all = c(0, head(custome_cumsum(helper_match_loss_all), n = -1)),
                rec_loss_sub = c(0, head(custome_cumsum(helper_match_loss_sub), n = -1)),
                rec_loss_ko = c(0, head(custome_cumsum(helper_match_loss_ko), n = -1)),
                rec_loss_decision = c(0, head(custome_cumsum(helper_match_loss_decision), n = -1)),
                rec_other = c(0, head(custome_cumsum(helper_match_other), n = -1)),
                rec_winrate = ifelse(is.nan(rec_wins_all/(rec_wins_all + rec_loss_all + rec_other)), yes = 0, no = rec_wins_all/(rec_wins_all + rec_loss_all + rec_other))) %>% 
  
  # Drop the helper and other columns
  dplyr::select(-c(tidyr::starts_with("helper"), winner_id, method, corner))

# --- 4. Prepare the final dataset ---------------------------------------------

FullPreparedData <- KaggleData[[4]] %>%  
  
  # Merge the changing variables. This has to be done twice - once for the red 
  # corner and once for the blue corner.
  dplyr::left_join(x = ., y = ChangingVariables, by = c("r_id" = "fighter_id", "fight_id" = "fight_id", "event_id" = "event_id", "date" = "date")) %>% 
  
  # Rename the columns regarding the records
  dplyr::rename(r_rec_wins_all = rec_wins_all, r_rec_wins_sub = rec_wins_sub, r_rec_wins_ko = rec_wins_ko, r_rec_wins_decision = rec_wins_decision, r_rec_loss_all = rec_loss_all, r_rec_loss_sub = rec_loss_sub, r_rec_loss_ko = rec_loss_ko, r_rec_loss_decision = rec_loss_decision, r_rec_other = rec_other, r_rec_winrate = rec_winrate) %>% 
  
  # Repeat this for the blue corner
  dplyr::left_join(x = ., y = ChangingVariables, by = c("b_id" = "fighter_id", "fight_id" = "fight_id", "event_id" = "event_id", "date" = "date")) %>% 
  
  dplyr::rename(b_rec_wins_all = rec_wins_all, b_rec_wins_sub = rec_wins_sub, b_rec_wins_ko = rec_wins_ko, b_rec_wins_decision = rec_wins_decision, b_rec_loss_all = rec_loss_all, b_rec_loss_sub = rec_loss_sub, b_rec_loss_ko = rec_loss_ko, b_rec_loss_decision = rec_loss_decision, b_rec_other = rec_other, b_rec_winrate = rec_winrate) %>% 
  
  # Calculate some other variables
  # Note: The 'difference' variables are based on the difference between the red
  #       and the blue fighter. We always subtract blue from red.
  dplyr::mutate(r_age = lubridate::interval(lubridate::ymd(r_dob), lubridate::ymd(date)) %/% months(1)/12,
                b_age = lubridate::interval(lubridate::ymd(b_dob), lubridate::ymd(date)) %/% months(1)/12,
                difference_wins = r_rec_wins_all - b_rec_wins_all,
                difference_loss = r_rec_loss_all - b_rec_loss_all,
                difference_age = r_age - b_age,
                difference_winrate = r_rec_winrate - b_rec_winrate) %>% 
  
  # Calculate some possible target variables
  dplyr::mutate(TotalSigStrikes = r_sig_str_landed + b_sig_str_landed,
                TotalTakedown = r_td_landed + b_td_landed,
                winner_red = winner_id == r_id) %>% 
  
  # Regroup some of the factor varibles
  
  
  # Change the type of somme variables in order for mlr3, etc. to work
  dplyr::mutate(dplyr::across(c(location, division, method, referee, r_id, b_id, r_stance, b_stance), as.factor))




FullPreparedData <- FullPreparedData %>%
  mutate(division = case_when(
    str_detect(division, "women's strawweight") ~ "women's strawweight",
    str_detect(division, "women's flyweight")   ~ "women's flyweight",
    str_detect(division, "women's bantamweight") ~ "women's bantamweight",
    str_detect(division, "women's featherweight") ~ "women's featherweight",
    str_detect(division, "light heavyweight")   ~ "light heavyweight",
    str_detect(division, "super heavyweight")   ~ "super heavyweight",
    str_detect(division, "heavyweight")         ~ "heavyweight",
    str_detect(division, "middleweight")        ~ "middleweight",
    str_detect(division, "welterweight")        ~ "welterweight",
    str_detect(division, "featherweight")       ~ "featherweight",
    str_detect(division, "lightweight")         ~ "lightweight",
    str_detect(division, "bantamweight")        ~ "bantamweight",
    str_detect(division, "flyweight")           ~ "flyweight",
    str_detect(division, "strawweight")         ~ "strawweight",
    TRUE ~ "other"
  ))

# --- 5. Partition the data into train, test and validation --------------------

PreparedTrainData <- subset(FullPreparedData, date < "2024-01-01")
PreparedTestData <- subset(FullPreparedData, date >= "2024-01-01" & date < "2025-01-01")
PreparedValidationData <- subset(FullPreparedData, date >= "2025-01-01")


# --- 6. Saving the prepared datasets ------------------------------------------

saveRDS(object = FullPreparedData, file = "Data/FullPreparedData.rds")
saveRDS(object = PreparedTrainData, file = "Data/PreparedTrainData.rds")
saveRDS(object = PreparedTestData, file = "Data/PreparedTestData.rds")
saveRDS(object = PreparedValidationData, file = "Data/PreparedValidationData.rds")

