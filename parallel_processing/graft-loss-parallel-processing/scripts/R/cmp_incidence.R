##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param time
##' @param status
cmp_incidence <- function(data, time, status) {
  
  total_events <- sum(getElement(data, status))
  total_time <- sum(getElement(data, time))
  
  estimate = total_events / total_time
  
  fit <- glm(total_events ~ offset(log(total_time)), family="poisson")
  
  fit_ci <- exp(confint(fit))
  
  list(incidence_est = estimate,
       incidence_lwr = fit_ci['2.5 %'],
       incidence_upr = fit_ci['97.5 %'])
  
}
