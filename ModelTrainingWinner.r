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
# mlr3temporal might need to be installed from GitHub, remotes::install_github("mlr-org/mlr3temporal")
pacman::p_load(dplyr, mlr3, mlr3viz, mlr3learners, mlr3pipelines, mlr3filters, mlr3tuning, future, mlr3temporal)

# Increase the number of used cores
future::plan("multisession", workers = availableCores() - 2)

# Set the seed, kind is needed due to parallel computing
set.seed(42, kind = "L'Ecuyer-CMRG")

# --- 2. Define some functions -------------------------------------------------


prepare_data <- function(my_data){
  
  my_data %>% 
    
    # Select the columns that will be used for the models
    dplyr::select(
      c(winner_red, date, title_fight, total_rounds, title_fight, 
        difference_wins, difference_loss, difference_age, difference_winrate,
        r_height, r_stance, r_age, r_rec_wins_all, r_rec_wins_ko, r_rec_wins_sub, r_rec_wins_decision, r_rec_loss_all, r_rec_loss_ko, r_rec_loss_sub, r_rec_loss_decision, 
        b_height, b_stance, b_age, b_rec_wins_all, b_rec_wins_ko, b_rec_wins_sub, b_rec_wins_decision, b_rec_loss_all, b_rec_loss_ko, b_rec_loss_sub, b_rec_loss_decision)) %>% 
    
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
      mtry.ratio = to_tune(c(seq(0.05, 0.5, 0.05))),
      splitrule = to_tune(c("gini", "extratrees", "hellinger"))
      )
  }
  else if(lrn_key == "classif.svm"){
    
    lrn_obj = mlr3::lrn(
      lrn_key,
      predict_type = "prob",
      type = "C-classification",
      kernel = to_tune(c("radial", "polynomial", "sigmoid")), # c("radial", "polynomial", "sigmoid")
      cost  = to_tune(1e-2, 1e3, logscale = logscale_trans),
      gamma = to_tune(1e-3, 1e1,   logscale = logscale_trans)
    )
  }
  else if(lrn_key == "classif.xgboost"){
    
    lrn_obj = mlr3::lrn(
      lrn_key, 
      predict_type = "prob",
      booster = to_tune(c("gbtree", "gblinear", "dart")),
      feature_selector = to_tune(c("cyclic", "shuffle"))
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

## --- 3.1 Load the datasets ---------------------------------------------------

TrainData <- readRDS("data/PreparedTrainData.rds") %>% prepare_data()

# Drop the earlier fights from the training data
TrainData <- TrainData %>% dplyr::arrange(date) %>% dplyr::slice_tail(n = 6500)

ValidationData <- readRDS("data/PreparedValidationData.rds") %>% prepare_data()

## --- 3.2 Set up the training/tuning task

tsk_Winner <- mlr3::as_task_classif(x = TrainData, target = "winner_red")
tsk_Winner$col_roles$order <- "date"
tsk_Winner$col_roles$feature <- setdiff(tsk_Winner$col_roles$feature, "date")

inner_resampling <- mlr3::rsmp("forecast_cv", folds = 3, window_size = 2000, horizon = 300, fixed_window = TRUE)
outer_resampling <- mlr3::rsmp("forecast_cv", folds = 5, window_size = 4000, horizon = 400, fixed_window = TRUE)

## --- 3.3 Set up the validation task

tsk_Validation <- mlr3::as_task_classif(x = ValidationData, target = "winner_red")
tsk_Validation$col_roles$order <- "date"
tsk_Validation$col_roles$feature <- setdiff(tsk_Validation$col_roles$feature, "date")

## --- 3.4 Set up the task for the final training (Training and Validation)

FinalData <- dplyr::bind_rows(TrainData, ValidationData)

tsk_Final <- mlr3::as_task_classif(x = FinalData, target = "winner_red")
tsk_Final$col_roles$order <- "date"
tsk_Final$col_roles$feature <- setdiff(tsk_Final$col_roles$feature, "date")

# --- 4. Set up the models -----------------------------------------------------

## --- 4.1 Random Forest -------------------------------------------------------

at_ranger <- mlr3tuning::auto_tuner(
  tuner      = mlr3tuning::tnr("grid_search", batch_size = availableCores() - 2),
  learner    = prepare_learner("classif.ranger"),
  resampling = inner_resampling,
  measure    = mlr3::msr("classif.bacc")
)

## --- 4.2 SVM -----------------------------------------------------------------


at_svm <- mlr3tuning::auto_tuner(
  tuner      = mlr3tuning::tnr("random_search", batch_size = availableCores() - 2),
  learner    = prepare_learner("classif.svm"),
  resampling = inner_resampling,
  measure    = mlr3::msr("classif.bacc"),
  terminator = mlr3tuning::trm("evals", n_evals = 20)
)

## --- 4.3 XGboost -------------------------------------------------------------

at_xgboost <- mlr3tuning::auto_tuner(
  tuner      = mlr3tuning::tnr("grid_search", batch_size = availableCores() - 2),
  learner    = prepare_learner("classif.xgboost"),
  resampling = inner_resampling,
  measure    = mlr3::msr("classif.bacc")
)

# --- 5. Compare and evaluate the models ---------------------------------------

design <- mlr3::benchmark_grid(
  tasks       = tsk_Winner,
  learners    = list(
    at_ranger, 
    at_svm, 
    at_xgboost),
  resamplings = outer_resampling
)

bmr <- mlr3::benchmark(design)
bmr$aggregate(mlr3::msr("classif.bacc"))

# --- 6. Check the performance on the validation data --------------------------

## ... 6.1 Set up the validation learners and retrain them ---------------------

validation_learners <- list(ranger = at_ranger, svm = at_svm, xgboost = at_xgboost)

validation_results <- lapply(names(validation_learners), function(lrn_name) {
  
  at <- validation_learners[[lrn_name]]
  
  at$train(tsk_Winner)
  pred <- at$predict(tsk_Validation)
  
  scores <- pred$score(mlr3::msrs(c("classif.bacc", "classif.acc", "classif.auc")))
  
  list(
    learner    = lrn_name,
    confusion  = pred$confusion,
    scores     = scores
  )
  
})

names(validation_results) <- names(validation_learners)

## --- 6.2 Show the performance ------------------------------------------------

# Print confusion matrices and scores per model
for (lrn_name in names(validation_results)) {
  cat("\n===", lrn_name, "===\n")
  print(validation_results[[lrn_name]]$confusion)
  print(validation_results[[lrn_name]]$scores)
}

# Combine scores into a single comparison table
dplyr::bind_rows(lapply(names(validation_results), function(lrn_name) { c(learner = lrn_name, validation_results[[lrn_name]]$scores) }))

# --- 7. Train and save the final model ----------------------------------------

## --- 7.1 Save the tuned models

for(lrn_name in names(validation_learners)) {
  saveRDS(validation_learners[[lrn_name]], file = paste0("models/Winner_Tuned_", lrn_name, ".rds"))
}

## --- 7.2 Train and save the models on all the data

final_learners <- list(ranger = at_ranger, svm = at_svm, xgboost = at_xgboost)

for (lrn_name in names(final_learners)) {
  final_learners[[lrn_name]]$train(tsk_Final)
  saveRDS(final_learners[[lrn_name]], file = paste0("models/Winner_Final_", lrn_name, ".rds"))
}



