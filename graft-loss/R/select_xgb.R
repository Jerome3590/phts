##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param trn
##' @param n_predictors
select_xgb <- function(trn,
                       n_predictors,
                       n_rounds = 250,
                       eta = 0.01,
                       max_depth = 3,
                       gamma = 1/2,
                       min_child_weight = 2,
                       subsample = 1/2,
                       colsample_bynode = 1/2,
                       objective = "survival:cox",
                       eval_metric = "cox-nloglik"
                       ) {

  trn_x <- as.matrix(select(trn, -c(time, status)))
  trn_y <- as.matrix(select(trn, c(time, status)))
  
  xgb_label <- trn_y[, 1]
  censored <- trn_y[, 2] == 0
  xgb_label[censored] <- xgb_label[censored] * (-1)
  
  params <- list(    
    eta = eta,
    max_depth = max_depth,
    gamma = gamma,
    min_child_weight = min_child_weight,
    subsample = subsample,
    colsample_bynode = colsample_bynode,
    objective = objective,
    eval_metric = eval_metric
  )
  
  sgb_trn <- sgb_data(data  = trn_x, 
                      label = xgb_label)
  
  sgb_fit(
    sgb_df = sgb_trn, 
    nrounds = n_rounds,
    verbose = 0,
    params = params
  ) %>% 
    use_series('fit') %>% 
    xgb.importance(model = .) %>% 
    slice(1:n_predictors) %>% 
    pull(Feature)

}
