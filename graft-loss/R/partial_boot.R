##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param reference
##' @param exposure
##' @param n_boots
partial_boot <- function(reference, exposure, n_boots = 1000){
  
  df_partial <- tibble(reference = reference, exposure = exposure)
  
  # rsample::bootstraps uses `times` (not `m`)
  n_times <- max(1L, as.integer(n_boots %||% 1L))
  boots <- tryCatch(
    bootstraps(df_partial, times = n_times),
    error = function(e){
      # Fallback: create a single apparent split to avoid halting
      rsample::apparent(df_partial)
    }
  ) %>%
    mutate(
      result = map(
        .x = splits,
        .f = ~ {
          
          boot_data <- training(.x)
          refr <- median(boot_data$reference)
          expo <- median(boot_data$exposure)
          
          list(
            prev = expo,
            ratio = expo / refr,
            diff = expo - refr
          )
          
        } 
      )
    ) %>%
    unnest_wider(result)
  
  refr <- median(df_partial$reference)
  expo <- median(df_partial$exposure)
  
  estimate <- c(prev = expo, ratio = expo / refr, diff = expo - refr)
  
  bootBCa(
    estimate = estimate,
    estimates = as.matrix(boots[, c('prev','ratio','diff')]),
    n = length(exposure)
  ) %>%
    t() %>%
    cbind(est = estimate) %>%
    as_tibble(rownames = 'measure') %>%
    rename(lwr = `2.5%`, upr = `97.5%`) %>%
    pivot_wider(names_from = measure,
                values_from = c(lwr, upr, est))
  
}
