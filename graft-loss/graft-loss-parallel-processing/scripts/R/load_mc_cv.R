##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title

load_mc_cv <- function() {

  bind_rows(
    read_rds(here::here('data', 'mc_cv_results_250.rds')),
    read_rds(here::here('data', 'mc_cv_results_500.rds')),
    read_rds(here::here('data', 'mc_cv_results_750.rds'))
  )

}
