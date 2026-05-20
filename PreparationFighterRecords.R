################################################################################
################################################################################
################################################################################
################                                                ################
################                Data Preparation                ################
################                Fighter Records                 ################
################                                                ################
################################################################################
################################################################################
################################################################################

# Clear the workspace
rm(list = ls())

# Load the needed packages
pacman::p_load(RKaggle, tidyr, dplyr)

# Load the dataset from Kaggle
AllFights <- RKaggle::get_dataset("neelagiriaditya/ufc-datasets-1994-2025")

# Extract if it is a win/loss/other of each fighter
FighterRecords <- AllFights[[4]] %>%
  
  # Choose the relevant columns
  dplyr::select(c(event_id, date, fight_id, r_id, b_id, winner_id)) %>%
  
  # Transform the wide dataframe to a long one, since we are not interested if the fighter is from the red or blue column
  tidyr::pivot_longer(cols = c(r_id, b_id), 
                      names_to = "corner", 
                      values_to = "fighter_id") %>% 
  
  # Create columns that check for win/loss/other
  # Here other stands for draws/NC or other
  dplyr::mutate(match_win = ifelse(test = winner_id == fighter_id, yes = 1, no = 0),
                match_loss = 1 - match_win,
                match_other = as.numeric(is.na(match_win)))

# Calculate/Extract the Fighter Records of each fighter with respect ot time
FighterRecords <- FighterRecords %>%
  
  # Sort the data according to the date of the fight
  dplyr::arrange(date) %>%
  
  # Replace the NA in the wins/loss/other with 0 to not confuse the cumsum
  dplyr::mutate(match_win = tidyr::replace_na(match_win, 0),
                match_loss = tidyr::replace_na(match_loss, 0),
                match_other = tidyr::replace_na(match_other, 0)) %>% 
  
  # Group by the fighter
  dplyr::group_by(fighter_id) %>%
  
  # Calculate the records
  dplyr::mutate(rec_wins = c(0, head(cumsum(match_win), n = -1)),
                rec_loss = c(0, head(cumsum(match_loss), n = -1)),
                rec_other = c(0, head(cumsum(match_other), n = -1))) %>%
  
  # Drop some columns
  dplyr::select(-c(match_win, match_loss, match_other, corner, winner_id))


# Save the fighter records data
saveRDS(object = FighterRecords, file = "Data/FighterRecords")


