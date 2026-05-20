# =============================================================================
# Model Training - Winner Prediction
# =============================================================================
# Description: This script trains various models to predict the winner
# Author:      Michael Schenk
# Date:        13.05.2026
# Dataset:     Prepared Data from Data.Preparation.r
# =============================================================================

# --- 1. Setup and packages ----------------------------------------------------

# Change the System Language
Sys.setLanguage("en")

# Clear the workspace 
rm(list = ls())

# Load the needed packages
pacman::p_load(dplyr, mlr3, mlr3viz, mlr3learners, mlr3pipelines, mlr3filters)

# --- 2. Define some functions -------------------------------------------------

prepare_data <- function(my_data){
  
  my_data %>% 
    
    dplyr::select(c(winner_red, date, division, title_fight, referee, total_rounds,
                              r_id, r_height, r_stance, r_age, r_rec_wins_all, r_rec_wins_ko, r_rec_wins_sub, r_rec_wins_decision, r_rec_loss_all, r_rec_loss_ko, r_rec_loss_sub, r_rec_loss_decision, r_rec_other,
                              b_id, b_height, b_stance, b_age, b_rec_wins_all, b_rec_wins_ko, b_rec_wins_sub, b_rec_wins_decision, b_rec_loss_all, b_rec_loss_ko, b_rec_loss_sub, b_rec_loss_decision, b_rec_other)) %>% 
    
    dplyr::filter(!is.na(winner_red))
  
}



prepare_learner <- function(lrn_key, remove_corr = FALSE) {
  
  
  lrn_obj = mlr3::lrn(lrn_key)
  possible_feature_types = lrn_obj$feature_types  
  
  lrn_pipeline = mlr3pipelines::po("select", selector = mlr3pipelines::selector_type(possible_feature_types)) %>>%
    
    # median is for numeric and mode for factor
    mlr3pipelines::po("imputemedian") %>>%
    mlr3pipelines::po("imputemode")
  
  #if (remove_corr) { lrn_pipeline = lrn_pipeline %>>% mlr3pipelines::po("correlation", cutoff = 0.99) }
  #if (remove_corr) { lrn_pipeline = lrn_pipeline %>>% po("filter", filter = flt("correlation"), filter.nfeat = 10) }
  if (remove_corr) { lrn_pipeline = lrn_pipeline %>>% mlr3pipelines::po("pca", rank. = 10) }
   
   
  lrn_pipeline %>>% 
    lrn_obj %>% 
    mlr3::as_learner()
  
}

# --- 3. Prepare the data ------------------------------------------------------

# Load the datasets
TrainData <- readRDS("Data/PreparedTrainData.rds")
TestData <- readRDS("Data/PreparedTestData.rds")

TrainData <- prepare_data(TrainData)
TestData <- prepare_data(TestData)

# --- 4. Construct the task, measures and learners -----------------------------

tsk_Winner <- mlr3::as_task_classif(x = TrainData, target = "winner_red", order = "date")

tsk_Winner$col_roles$feature <- setdiff(tsk_Winner$col_roles$feature, "date")

measures <- mlr3::msrs(c("classif.acc", "classif.bacc"))


lrn_glmnet     <- prepare_learner(lrn_key = "classif.glmnet")
lrn_knn        <- prepare_learner(lrn_key = "classif.kknn")
lrn_lda        <- prepare_learner(lrn_key = "classif.lda", remove_corr = TRUE)
lrn_logreg     <- prepare_learner(lrn_key = "classif.log_reg")
lrn_naivebayes <- prepare_learner(lrn_key = "classif.naive_bayes")
lrn_qda        <- prepare_learner(lrn_key = "classif.qda")
lrn_svm        <- prepare_learner(lrn_key = "classif.svm")
lrn_ranger     <- prepare_learner(lrn_key = "classif.ranger")
lrn_xgboost    <- prepare_learner(lrn_key = "classif.xgboost")


# --- 5. Train the models ------------------------------------------------------

lrn_glmnet$train(tsk_Winner)
lrn_knn$train(tsk_Winner)
lrn_lda$train(tsk_Winner)
lrn_logreg$train(tsk_Winner)
lrn_naivebayes$train(tsk_Winner)
lrn_qda$train(tsk_Winner)
lrn_ranger$train(tsk_Winner)
lrn_svm$train(tsk_Winner)
lrn_xgboost$train(tsk_Winner)


# --- 6. Predict on the test data ----------------------------------------------

lrn_glmnet$predict_newdata(TestData)$score(measures)
lrn_knn$predict_newdata(TestData)$score(measures)
lrn_lda$predict_newdata(TestData)$score(measures)
lrn_logreg$predict_newdata(TestData)$score(measures)
lrn_naivebayes$predict_newdata(TestData)$score(measures)
lrn_qda$predict_newdata(TestData)$score(measures)
lrn_ranger$predict_newdata(TestData)$score(measures)
lrn_svm$predict_newdata(TestData)$score(measures)
lrn_xgboost$predict_newdata(TestData)$score(measures)


