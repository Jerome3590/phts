##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param trn
##' @param vars
##' @param tst
##' @param predict_horizon
fit_cph <- function(trn, vars = NULL, tst = NULL, predict_horizon = NULL) {
  
  # Track which variables were actually used
  vars_used <- vars
  
  # Fit model with error handling for constant columns
  fit_result <- tryCatch({
    model_fit <- safe_coxph(
      data = trn[, c(vars, 'time', 'status')],
      x = TRUE
    )
    list(model = model_fit, vars_used = vars)
  }, error = function(e) {
    # Check if error is related to constant/singular matrix
    if (grepl("constant|singular|colinear", e$message, ignore.case = TRUE)) {
      cat(sprintf("[CPH_WARNING] Matrix issue detected, attempting to fit without problematic variables\n"))
      
      # Find constant columns in this fold
      constant_vars <- character(0)
      for (v in vars) {
        if (v %in% names(trn)) {
          if (is.numeric(trn[[v]])) {
            if (length(unique(trn[[v]][!is.na(trn[[v]])])) <= 1) {
              constant_vars <- c(constant_vars, v)
            }
          }
        }
      }
      
      if (length(constant_vars) > 0) {
        cat(sprintf("[CPH_WARNING] Removing %d constant variables: %s\n", 
                    length(constant_vars), paste(constant_vars, collapse = ", ")))
        vars_filtered <- setdiff(vars, constant_vars)
        
        if (length(vars_filtered) == 0) {
          stop("All variables are constant in this fold - cannot fit model")
        }
        
        # Retry with filtered variables
        model_fit <- safe_coxph(
          data = trn[, c(vars_filtered, 'time', 'status')],
          x = TRUE
        )
        list(model = model_fit, vars_used = vars_filtered)
      } else {
        # Re-throw the original error if we couldn't identify constant columns
        stop(e)
      }
    } else {
      # Re-throw non-matrix errors
      stop(e)
    }
  })
  
  model <- fit_result$model
  vars_used <- fit_result$vars_used
  
  # Attach metadata to model for prediction
  attr(model, "vars_used") <- vars_used
  
  if(is.null(tst)) return(model)
  
  if(is.null(predict_horizon)) stop("specify prediction horizon", call. = F)
  if (!requireNamespace('riskRegression', quietly = TRUE)) stop("Package 'riskRegression' is required for fit_cph predictions. Please install it.")
  
  # Use only the variables that were used in training
  predictions <- riskRegression::predictRisk(model, newdata = tst[, vars_used], times = predict_horizon)
  
  # Ensure we return a numeric vector
  as.numeric(predictions)
}
