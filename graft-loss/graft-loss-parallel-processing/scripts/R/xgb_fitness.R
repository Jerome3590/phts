##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param input_string
##' @param trn_x
##' @param trn_label
##' @param folds
##' @param predict_horizon
##' 
xgb_fitness <- function(
  input_string,
  trn_x,
  trn_label,
  trn_time,
  trn_status,
  folds,
  predict_horizon) {
  
  params <- list(    
    eta              = as.numeric(input_string[1]),
    max_depth        = round(as.numeric(input_string[2])),
    gamma            = as.numeric(input_string[3]),
    min_child_weight = as.numeric(input_string[4]),
    subsample        = as.numeric(input_string[5]),
    colsample_bynode = as.numeric(input_string[6]),
    objective        = "survival:aft",
    eval_metric      = "aft-nloglik"
  )
  
  n_pred <- round(as.numeric(input_string[7]))
  n_rounds <- round(as.numeric(input_string[8]))
  
  # Format labels for XGBoost AFT
  xgb_label_lower <- trn_time
  xgb_label_upper <- ifelse(trn_status == 1, trn_time, Inf)
  
  auc_vals <- rep(NA_real_, length(folds))
  
  for(f in seq_along(folds)){
    
    test_index <- folds[[f]]
    
    # Create DMatrix for initial training with AFT labels
    dtrain_init <- xgboost::xgb.DMatrix(trn_x[-test_index, ])
    xgboost::setinfo(dtrain_init, 'label_lower_bound', xgb_label_lower[-test_index])
    xgboost::setinfo(dtrain_init, 'label_upper_bound', xgb_label_upper[-test_index])
    
    predictors <- xgb.train(params = params,
                           data = dtrain_init,
                           nrounds = n_rounds,
                           verbose = 0) %>% 
      xgb.importance(model = .) %>% 
      slice(1:n_pred) %>% 
      pull(Feature)
    
    # Create DMatrix for reduced training with AFT labels
    dtrain_rdcd <- xgboost::xgb.DMatrix(trn_x[-test_index, predictors])
    xgboost::setinfo(dtrain_rdcd, 'label_lower_bound', xgb_label_lower[-test_index])
    xgboost::setinfo(dtrain_rdcd, 'label_upper_bound', xgb_label_upper[-test_index])
    
    fit <- xgb.train(params = params,
                     data = dtrain_rdcd,
                     nrounds = n_rounds,
                     verbose = 0)
    
    # Create DMatrix for testing
    dtest_rdcd <- xgboost::xgb.DMatrix(trn_x[test_index, predictors])
    
    predictions <- list(
      predict(fit, dtest_rdcd)
    )
    
    score_data <- tibble(time = abs(trn_label[test_index]),
                         status = as.numeric(trn_label[test_index] > 0))
    
    evaluation <- Score(
      object = predictions,
      formula = Surv(time, status) ~ 1, 
      data = score_data, 
      times = predict_horizon, 
      se.fit = FALSE
    )
    
    auc_vals[f] <- evaluation$AUC$score$AUC
    
  }
  
  mean(auc_vals)
  
}


# min_predictors <- min(3, n_predictors)
# max_predictors <- max(min_predictors, n_predictors)
# 
# lower <- c(0.005, 1, 0.01, 0.01, 0.05, 0.05, min_predictors, 100)
# upper <- c(0.100, 5, 3.00, 3.00, 0.95, 0.95, max_predictors, 2000)
# 
# suggestions <- as.matrix(tibble(
#   eta = c(0.01),
#   max_depth = c(1,2,3,4,5),
#   gamma = c(0.5),
#   min_child_weight = c(2),
#   subsample = c(0.50), 
#   colsample_bynode = (0.25),
#   n_pred = n_predictors - 2,
#   n_rounds = c(1000)
# ))

# ga_tuner <- ga(
#   type    = 'real-valued',
#   fitness = xgb_fitness,
#   trn_x   = trn_x,
#   trn_label = xgb_label,
#   folds   = folds,
#   predict_horizon = predict_horizon,
#   suggestions = suggestions,
#   run     = 5,
#   maxiter = 20,
#   popSize = 35,
#   lower   = lower,
#   upper   = upper,
#   population = gareal_Population
# )
# 
# tuned_solution <- as.numeric(ga_tuner@solution)
# 
# tuned_params <- list(
#   eta              = tuned_solution[1],
#   max_depth        = round(tuned_solution[2]),
#   gamma            = tuned_solution[3],
#   min_child_weight = tuned_solution[4],
#   subsample        = tuned_solution[5],
#   colsample_bynode = tuned_solution[6],
#   objective        = "survival:cox",
#   eval_metric      = "cox-nloglik"
# )
# 
# n_pred <- round(tuned_solution[7])
# n_rounds <- round(tuned_solution[8])