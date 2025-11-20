##' Create recipe for Monte Carlo Cross Validation
##'
##' This is a specialized version of make_recipe that skips near-zero variance
##' filtering to preserve variables selected on the full dataset. The NZV step
##' can inappropriately drop variables in small MC-CV training splits that were
##' valid predictors in the full dataset.
##'
##' @param data Training data for the MC-CV split
##' @param dummy_code Whether to create dummy variables (default: TRUE)
##' @param add_novel Whether to add novel level handling (default: TRUE)
##' @return Recipe object without NZV filtering
##' @title Make Recipe for MC-CV (No NZV Filtering)

make_recipe_mc_cv <- function(data, dummy_code = TRUE, add_novel = TRUE) {
  
  naming_fun <- function(var, lvl, ordinal = FALSE, sep = '..'){
    dummy_names(var = var, lvl = lvl, ordinal = ordinal, sep = sep)
  }

  rc <- recipe(time + status ~ ., data)
  # Only set ID role if present to avoid selection errors in downstream steps
  if ('ID' %in% names(data)) {
    rc <- rc %>% update_role(ID, new_role = 'Patient identifier')
  }
  rc <- rc %>%
    step_impute_median(all_numeric(), -all_outcomes()) %>%
    step_impute_mode(all_nominal(), -all_outcomes()) %>%
    # CRITICAL: Skip step_nzv() for MC-CV to preserve variable selection
    # step_nzv(all_predictors(), freq_cut = 1000, unique_cut = 0.025) %>% 
    #step_other(all_nominal(), -all_outcomes(), other = 'Other') %>%
    # Optionally add a guaranteed-unique token for novel levels; skip if data already preprocessed
    {
      if (isTRUE(add_novel)) {
        step_novel(., all_nominal(), -all_outcomes(), new_level = '.novel__recipes__')
      } else {
        .
      }
    }
  
  if(dummy_code){
    rc %>%
      step_dummy(
        all_nominal(), -all_outcomes(), 
        naming = naming_fun,
        one_hot = FALSE
      )
  } else {
    rc
  }

}
