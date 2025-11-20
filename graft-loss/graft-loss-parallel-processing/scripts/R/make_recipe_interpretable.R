##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title

make_recipe_interpretable <- function(phts_all) {

  naming_fun <- function(var, lvl, ordinal = FALSE, sep = '..'){
    dummy_names(var = var, lvl = lvl, ordinal = ordinal, sep = sep)
  }
  
  recipe(time + status ~ ., phts_all) %>%
    step_impute_median(all_numeric(), -all_outcomes()) %>%
    step_impute_mode(all_nominal(), -all_outcomes()) %>%
    step_nzv(all_predictors(), freq_cut = 1000, unique_cut = 0.025) %>% 
    step_discretize(
      all_numeric(),
      -all_outcomes(),
      num_breaks = 3
    )
  
}
