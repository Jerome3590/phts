##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param trn
##' @param n_predictors
select_rsf <- function(trn, 
                       n_predictors,
                       num.trees = 250,
                       importance = 'permutation',
                       min.node.size = 20,
                       splitrule = 'extratrees',
                       num.random.splits = 10,
                       return_importance = FALSE) {

  model <- ranger(
    formula = Surv(time, status) ~ .,
    data = trn,
    num.trees = num.trees,
    importance = importance,
    min.node.size = min.node.size,
    splitrule = splitrule,
    num.random.splits = num.random.splits
  )
  
  ftr_importance <- enframe(model$variable.importance) %>% 
    arrange(desc(value)) %>% 
    slice(1:n_predictors)
  
  if(return_importance) return(ftr_importance)
  
  pull(ftr_importance, name)

}
