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
pacman::p_load(dplyr, mlr3, mlr3viz, mlr3learners, mlr3pipelines, mlr3filters, mlr3tuning, future)

# Increase the number of used cores
future::plan("multisession", workers = availableCores() - 2)

# Set the seed, kind is needed due to parallel computing
set.seed(42, kind = "L'Ecuyer-CMRG")

# --- 2. Define some functions -------------------------------------------------

prepare_data <- function(my_data){
  
  my_data %>% 
    
    dplyr::mutate(date = as.integer(date)) %>% 
    
    dplyr::select(c(winner_red, date, title_fight, total_rounds,
                              r_height, r_stance, r_age, r_rec_wins_all, r_rec_wins_ko, r_rec_wins_sub, r_rec_wins_decision, r_rec_loss_all, r_rec_loss_ko, r_rec_loss_sub, r_rec_loss_decision, r_rec_other,
                              b_height, b_stance, b_age, b_rec_wins_all, b_rec_wins_ko, b_rec_wins_sub, b_rec_wins_decision, b_rec_loss_all, b_rec_loss_ko, b_rec_loss_sub, b_rec_loss_decision, b_rec_other)) %>% 
    
    dplyr::filter(!is.na(winner_red))
  
}



prepare_learner <- function(lrn_key, remove_corr = FALSE, logscale_trans = TRUE) {
  
  # Each model needs a different setup regarding the tuning
  if(lrn_key == "classif.ranger"){
    
    lrn_obj = mlr3::lrn(
      lrn_key,
      num.threads = 1,
      predict_type = "prob",
      num.trees = to_tune(500),
      mtry.ratio = to_tune(c(seq(0.1, 0.5, 0.1))),
      splitrule = to_tune(c("gini", "extratrees", "hellinger"))
      )
  }
  else if(lrn_key == "classif.svm"){
    
    lrn_obj = mlr3::lrn(
      lrn_key,
      predict_type = "prob",
      type = "C-classification",
      #kernel = to_tune(c("radial", "linear")),
      kernel = to_tune(c("linear")),
      cost  = to_tune(1e-2, 1e3, logscale = logscale_trans),
      gamma = to_tune(1e-3, 1e1,   logscale = logscale_trans)
    )
  }
  else{

    lrn_obj = mlr3::lrn(lrn_key)
    
  }
  
  possible_feature_types = lrn_obj$feature_types

  lrn_pipeline = mlr3pipelines::po("select", selector = mlr3pipelines::selector_type(possible_feature_types)) %>>%

   # median is for numeric and mode for factor
    mlr3pipelines::po("imputemedian") %>>%
    mlr3pipelines::po("imputemode")
   
  
   
   
  lrn_pipeline %>>% lrn_obj %>% mlr3::as_learner()

  
}

# --- 3. Prepare the data, task and measures -----------------------------------

# Load the datasets
TrainData <- readRDS("data/PreparedTrainData.rds")
TestData <- readRDS("data/PreparedTestData.rds")

TrainData <- prepare_data(TrainData)
TestData <- prepare_data(TestData)

tsk_Winner <- mlr3::as_task_classif(x = TrainData, target = "winner_red")
tsk_Winner$col_roles$order <- "date"
tsk_Winner$col_roles$feature <- setdiff(tsk_Winner$col_roles$feature, "date")



# --- 4. Tune and Test the models ----------------------------------------------

## --- 4.1 Random Forest -------------------------------------------------------

lrn_ranger <- prepare_learner(lrn_key = "classif.ranger")

instance_ranger <- mlr3tuning::tune(
  tuner = mlr3tuning::tnr("grid_search", resolution = 5, batch_size = availableCores() - 2),
  task = tsk_Winner,
  learner = lrn_ranger,
  resampling = mlr3::rsmp("holdout", ratio = 0.8),
  measures = mlr3::msr("classif.bacc"),
  store_benchmark_result = TRUE
)


as.data.table(instance_ranger$archive, measures = mlr3::msrs(c("classif.auc", "classif.ce"))) %>% View()

lrn_ranger$param_set$values <- instance_ranger$result_learner_param_vals

lrn_ranger$train(tsk_Winner)

lrn_ranger$predict_newdata(TestData)$score(mlr3::msrs(c("classif.bacc", "classif.auc", "classif.ce")))

## --- 4.2 SVM -----------------------------------------------------------------

lrn_svm <- prepare_learner(lrn_key = "classif.svm")

instance_svm <- mlr3tuning::tune(
  tuner = mlr3tuning::tnr("random_search", batch_size = availableCores() - 2),
  task = tsk_Winner, 
  learner = lrn_svm,
  resampling = mlr3::rsmp("holdout", ratio = 0.8),
  measures = mlr3::msr("classif.bacc"), 
  terminator = mlr3tuning::trm("evals", n_evals = 30)
)

as.data.table(instance_svm$archive, measures = mlr3::msrs(c("classif.auc", "classic.ce"))) %>% View()

lrn_svm$param_set$values <- instance_svm$result_learner_param_vals

lrn_svm$train(tsk_Winner)

lrn_svm$predict_newdata(TestData)$score(mlr3::msrs(c("classif.bacc", "classif.auc", "classif.ce")))

# --- 5. Compare the models on the test data -----------------------------------


# --- 6. Train and save the final model ----------------------------------------
