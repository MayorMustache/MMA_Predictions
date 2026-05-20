
pacman::p_load(dplyr, GFDrmst, GFDrmtl)

UFC <- read.csv2("archive/ufc_fighters_final.csv", sep = ",")
FightData <- read.csv2("archive/ufc_gold_dataset_final.csv", sep = ",")
FightData$SurvivalTime <- sapply(strsplit(FightData$End_Time, split = ":"), function(x) as.numeric(x[[1]])*60+as.numeric(x[[2]])) + (FightData$End_Round-1)*300
FightData$SurvivalEventKO <- FightData$Method == "KO/TKO"
FightData$SurvivalEventSub <- FightData$Method == "Submission"
FightData$SurvivalEventRisk <- ifelse(FightData$SurvivalEventKO, yes = 1, no = ifelse(FightData$SurvivalEventSub, yes = 2, no = 0))

FightData <- FightData %>% 
  filter(Weight_Class %in% c("Lightweight Bout", "Heavyweight Bout", "Welterweight Bout", "Middleweight Bout", "Light Heavyweight Bout", "Flyweight Bout", "Featherweight Bout", "Bantamweight Bout")) %>% 
  mutate(Weight_Class = factor(Weight_Class, levels = c("Flyweight Bout", "Bantamweight Bout", "Featherweight Bout", "Lightweight Bout", "Welterweight Bout", "Middleweight Bout", "Light Heavyweight Bout", "Heavyweight Bout")))


system.time(Ding <- RMST.test(time = FightData$SurvivalTime, status = FightData$SurvivalEventSub, group = FightData$Weight_Class, tau = 1500, hyp_mat = "Tukey", method = "asymptotic"))
system.time(Ding2 <- RMTL.test(time = FightData$SurvivalTime, status = FightData$SurvivalEventRisk, group = FightData$Weight_Class, tau = 1500, hyp_mat = "Tukey", method = "asymptotic"))

summary(Ding)
summary(Ding2)
