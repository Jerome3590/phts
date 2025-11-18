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
  
  step_init <- coxph(Surv(time, status) ~ 1, data = trn, x = TRUE)
  
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
    objective        = "survival:cox",
    eval_metric      = "cox-nloglik"
  )
  
  xgb_label <- trn$time
  censored <- trn$status == 0
  xgb_label[censored] <- xgb_label[censored] * (-1) 
  
  xgb_cv <- xgb.cv(params = xgb_params,
                   data = trn_xgb,
                   nrounds = 2500,
                   nfold = 10,
                   early_stopping_rounds = 100,
                   label = xgb_label,
                   verbose = 0)
  
  booster <- sgb_fit(
    sgb_df = sgb_data(data = trn_xgb, label = xgb_label),
    nrounds = xgb_cv$best_iteration,
    params = xgb_params
  )
  
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
  
  predicted_risk_cph <- predictRisk(
    step_fit,
    newdata = tst,
    times = predict_horizon
  )
  
  predicted_risk_xgb <- 1 - predict(
    booster,
    new_data = as.matrix(as_tibble(tst)[, step_vars]),
    eval_times = predict_horizon
  )
  
  predicted_risk_orsf <- 1 - predict(
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

