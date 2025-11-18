##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @param data 
##'
##' @title

make_recipe <- function(data, dummy_code = TRUE, add_novel = TRUE) {
  
  naming_fun <- function(var, lvl, ordinal = FALSE, sep = '..'){
    dummy_names(var = var, lvl = lvl, ordinal = ordinal, sep = sep)
  }

  rc <- recipe(time + status ~ ., data)
  # Only set ID role if present to avoid selection errors in downstream steps
  if ('ID' %in% names(data)) {
    rc <- rc %>% update_role(ID, new_role = 'Patient identifier')
  }
  
  # Define Wisotzkey features that should never be removed by NZV filter
  # These are clinically important predictors even if they have low variance
  wisotzkey_protected <- c("prim_dx", "tx_mcsd", "chd_sv", "hxsurg", "txsa_r", 
                           "txbun_r", "txecmo", "txpl_year", "weight_txpl", "txalt",
                           "bmi_txpl", "pra_listing", "egfr_tx", "hxmed", "listing_year")
  
  rc <- rc %>%
    step_impute_median(all_numeric(), -all_outcomes()) %>%
    step_impute_mode(all_nominal(), -all_outcomes()) %>%
    # Apply NZV filter but exclude protected Wisotzkey features
    step_nzv(all_predictors(), -any_of(wisotzkey_protected), freq_cut = 1000, unique_cut = 0.025) %>% 
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
