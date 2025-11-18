##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param trn
##' @param n_predictors
select_cph <- function(trn, n_predictors) {

  step_init <- coxph(Surv(time, status) ~ 1, data = trn, x = TRUE)
  
  step_scope_rhs <- trn %>% 
    select(-time, -status) %>% 
    names() %>% 
    glue_collapse(sep = ' + ')
  
  step_scope <- as.formula(glue("Surv(time, status) ~ {step_scope_rhs}"))
  
  step_fit <- stepAIC(object = step_init, 
                      scope = step_scope, 
                      direction = 'both', 
                      steps = n_predictors,
                      trace = 0)
  
  names(step_fit$coefficients)

}
