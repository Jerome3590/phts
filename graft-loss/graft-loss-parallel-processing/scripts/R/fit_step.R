##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##'
##' @param trn 
##' @param tst 
##' @param n_predictors 
##' @param predict_horizon 
##' 
fit_step <- function(trn,
                     tst,
                     return_fit,
                     predict_horizon,
                     n_predictors) {
  
  step_init <- survival::coxph(Surv(time, status) ~ 1, data = trn, x = TRUE)
  
  step_scope_rhs <- trn %>% 
    select(-time, -status) %>% 
    names() %>% 
    glue_collapse(sep = ' + ')
  
  step_scope <- as.formula(glue("Surv(time, status) ~ {step_scope_rhs}"))
  
  step_fit <- stepAIC(object = step_init, 
                      scope = step_scope, 
                      direction = 'both', 
                      steps = n_predictors,
                      trace = 0)
  
  
  step_vars <- names(step_fit$coefficients)
  
  trn_xgb <- as.matrix(trn[, step_vars])
  
  xgb_params <- list(    
    eta              = 0.01,
    max_depth        = 2,
    gamma            = 1/2,
    min_child_weight = 1,
    subsample        = 2/3,
    colsample_bynode = 1/3,
    objective        = "survival:aft",
    eval_metric      = "aft-nloglik"
  )
  
  # Format labels for XGBoost AFT
  time_values <- trn$time
  status_values <- trn$status
  xgb_label_lower <- time_values
  xgb_label_upper <- ifelse(status_values == 1, time_values, Inf)
  
  # Create DMatrix for cross-validation with AFT labels
  dtrain <- xgboost::xgb.DMatrix(trn_xgb)
  xgboost::setinfo(dtrain, 'label_lower_bound', xgb_label_lower)
  xgboost::setinfo(dtrain, 'label_upper_bound', xgb_label_upper)
  
  xgb_cv <- xgb.cv(params = xgb_params,
                   data = dtrain,
                   nrounds = 2500,
                   nfold = 10,
                   early_stopping_rounds = 100,
                   verbose = 0)
  
  # Create DMatrix for final model with AFT labels
  dtrain_final <- xgboost::xgb.DMatrix(trn_xgb)
  xgboost::setinfo(dtrain_final, 'label_lower_bound', xgb_label_lower)
  xgboost::setinfo(dtrain_final, 'label_upper_bound', xgb_label_upper)
  
  booster <- xgb.train(params = xgb_params,
                       data = dtrain_final,
                       nrounds = xgb_cv$best_iteration,
                       verbose = 0)
  
  orsf_trn <- as_tibble(trn)[, c('time', 'status', step_vars)]
  orsf_tst <- as_tibble(tst)[, c('time', 'status', step_vars)]
  
  orsf_model <- ORSF(orsf_trn, ntree = 1000)
  
  rsf_model <- ranger(
    formula = Surv(time, status) ~ .,
    data = orsf_trn,
    num.trees = 1000,
    min.node.size = 10,
    splitrule = 'C'
  )
  
  if (return_fit) return(list(booster = booster, 
                              cph = step_fit, 
                              orsf = orsf_model,
                              rsf = rsf_model))
  
  predicted_risk_cph <- riskRegression::predictRisk(
    step_fit,
    newdata = tst,
    times = predict_horizon
  )
  
  # Use safe wrapper for XGB predictions to tolerate different predict signatures
  predicted_risk_xgb <- tryCatch({
    safe_model_predict(booster, new_data = as.matrix(as_tibble(tst)[, step_vars]))
  }, error = function(e) {
    # fallback: return NA (safe wrapper failed)
    NA_real_
  })
  
  predicted_risk_orsf <- 1 - safe_model_predict(
    orsf_model,
    newdata = orsf_tst,
    times = predict_horizon
  )
  
  predicted_risk_rsf <- ranger_predictrisk(
    rsf_model, 
    newdata = orsf_tst, 
    times = predict_horizon
  )
  
  score_data <- select(tst, time, status)
  
  xgb_scores <- fit_evaluation(predicted_risk = predicted_risk_xgb,
                               predict_horizon = predict_horizon,
                               score_data = score_data,
                               fit_label = 'xgb',
                               ftr_label = 'step')
  
  orsf_scores <- fit_evaluation(predicted_risk = predicted_risk_orsf,
                                predict_horizon = predict_horizon,
                                score_data = score_data,
                                fit_label = 'orsf',
                                ftr_label = 'step')
  
  cph_scores <- fit_evaluation(predicted_risk = predicted_risk_cph,
                               predict_horizon = predict_horizon,
                               score_data = score_data,
                               fit_label = 'cph',
                               ftr_label = 'step')
  
  rsf_scores <- fit_evaluation(predicted_risk = predicted_risk_rsf,
                               predict_horizon = predict_horizon,
                               score_data = score_data,
                               fit_label = 'rsf',
                               ftr_label = 'step')
  
  bind_rows(xgb_scores, orsf_scores, cph_scores)
  
}

