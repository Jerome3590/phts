##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param phts_all
##' @param ntimes
mc_cv_light <- function(phts_all, train_prop = 3/4, ntimes) {

  
  resamples <- mc_cv(data = phts_all,
                     prop = train_prop, 
                     times = ntimes,
                     strata = status)
  
  testing_rows <- map(resamples$splits, rsample::complement)
  
  write_rds(testing_rows, 'data/resamples.rds')
  
  testing_rows
  
}
