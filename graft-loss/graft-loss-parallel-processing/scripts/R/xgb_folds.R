##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param data
##' @param nfolds
xgb_folds <- function(data, nfolds){
  
  if(nrow(data) < nfolds)
    stop("nfolds must be >= number of rows in data")
  
  rsamp_folds <- rsample::vfold_cv(data, v=nfolds, strata = strata)
  purrr::map(rsamp_folds$splits, rsample::complement)
  
}
