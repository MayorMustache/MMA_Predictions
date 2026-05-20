################################################################################
################################################################################
################################################################################
################                                                ################
################                Data Preparation                ################
################              Train Test Validation             ################
################                                                ################
################################################################################
################################################################################
################################################################################

# Clear the workspace
rm(list = ls())

# Load the needed packages
pacman::p_load(dplyr, RKaggle, tidyr)

# Load the needed data from Kaggle
AllFights <- RKaggle::get_dataset("neelagiriaditya/ufc-datasets-1994-2025")

# Load the fighter Records
FighteRecords <- readRDS("Data/FighterRecords")

## Add the fighter records to the data
## This has to be done twice in order to differentiate between the red and blue corner
# Red corner
MainData <- dplyr::left_join(x = AllFights[[4]], y = FighteRecords, by = c("r_id" = "fighter_id", "fight_id" = "fight_id", "event_id" = "event_id", "date" = "date")) %>%
  # Rename the columns regarding the red corner
  dplyr::rename(r_rec_wins = rec_wins, r_rec_loss = rec_loss, r_rec_other = rec_other)

# Blue Corner
MainData <- dplyr::left_join(x = MainData, y = FighteRecords, by = c("b_id" = "fighter_id", "fight_id" = "fight_id", "event_id" = "event_id", "date" = "date")) %>%
  # Rename the columns regarding the red corner
  dplyr::rename(b_rec_wins = rec_wins, b_rec_loss = rec_loss, b_rec_other = rec_other)


## Add some target variables
# Add a column indicating if the fight ended in a Decision
MainData$Decision <- MainData$method %in% unique(MainData$method)[c(2,4,8)]

# Add a column for the combined significant strikes
MainData$TotalSigStrikes <- MainData$r_sig_str_landed + MainData$b_sig_str_landed

# Add a column indicating if the winning corner is red or blue
MainData$winner_corner <- as.factor(ifelse(test = MainData$winner_id == MainData$r_id, yes = "red", no = ifelse(test = MainData$winner_id == MainData$b_id, yes = "blue", no = NA)))

# Add a column indicating if the fight goes to a decision
MainData$Decision <- grepl("Decision", MainData$method)

# Partition the data into train, test and validation
TrainData <- subset(MainData, date < "2024-01-01")
TestData <- subset(MainData, date >= "2024-01-01" & date < "2025-01-01")
ValidationData <- subset(MainData, date >= "2025-01-01")

# Save the data
saveRDS(object = TrainData, file = "Data/TrainData")
saveRDS(object = TestData, file = "Data/TestData")
saveRDS(object = ValidationData, file = "Data/ValidationData")