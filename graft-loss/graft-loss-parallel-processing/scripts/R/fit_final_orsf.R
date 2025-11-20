##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param phts_all
fit_final_orsf <- function(phts_all, n_predictors = 35) {

  .recipe   <- prep(make_recipe(data = phts_all))
  
  trn = juice(.recipe)
  
  feature_selector <- ranger(
    formula = Surv(time, status) ~ .,
    data = trn,
    num.trees = 250,
    importance = 'permutation',
    min.node.size = 20,
    splitrule = 'extratrees',
    num.random.splits = 10
  )
  
  rsf_vars <- c(
    'time', 'status', 
    get_topvars(feature_selector, n_predictors = n_predictors)
  )
  
  orsf_model <- ORSF(trn[, rsf_vars], 
                     ntree = 100, 
                     compute_oob_predictions = TRUE, 
                     eval_times = c(3, 6, 9, 12) / 12)
  
  
  orsf_risk_1yr <- 1 - orsf_model$oob_preds[, 4]
  
  ggdat <- bind_cols(risk_1yr = orsf_risk_1yr, 
                     orsf_model$data)
  
  # ggdat %>% 
  #   group_by(hxsurg..yes) %>% 
  #   summarize(risk = mean(risk_1yr))

  ggplot(ggdat, aes(x = cpbypass, y = risk_1yr)) + 
    geom_smooth()
  
  vdplot(
    object = orsf_model,
    xvar = 'hxsurg..yes',
    fvar = 'prim_dx..congenital_hd',
  )
  
  vdplot(orsf_model, xvar = 'cpbypass')
  
  vdplot(orsf_model, xvar = 'txinhosp..yes')
  
  p <- pdplot(orsf_model, xvar = 'cpbypass')
  
  
  

}
