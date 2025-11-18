##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##'
##' @param time 
##' @param status 
##' @param x 
##' @param data
safe_coxph <- function(data, 
                       time = 'time', 
                       status = 'status', 
                       x = TRUE){
  
  formula <- as.formula(glue("Surv({time}, {status}) ~ ."))
  
  cph_model <- coxph(formula = formula, data = data, x = x)
  
  data_refit <- data
  
  while ( any(is.na(cph_model$coefficients)) ) {
    
    na_index <- which(is.na(cph_model$coefficients))
    to_drop <- names(cph_model$coefficients)[na_index]
    data_refit[, to_drop] <- NULL
    cph_model <- coxph(formula = formula, data = data_refit, x = x)
    
  }
  
  cph_model
  
}
