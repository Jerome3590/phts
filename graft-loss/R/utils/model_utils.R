##' Model fitting and evaluation utilities
##' 
##' Collection of helper functions for model training and assessment

##' Standardized model fitting with error handling
##' @param fit_fn Model fitting function
##' @param data Training data
##' @param ... Additional arguments to fit_fn
safely_fit_model <- function(fit_fn, data, model_name = "Unknown", ...) {
  tryCatch({
    result <- fit_fn(data, ...)
    message(sprintf("✓ Successfully fitted %s model", model_name))
    return(result)
  }, error = function(e) {
    warning(sprintf("✗ Failed to fit %s model: %s", model_name, e$message))
    return(NULL)
  })
}

##' Standardized C-index computation with both Harrell and Uno methods
##' @param time Survival times
##' @param status Event indicators
##' @param predictions Risk predictions
##' @param eval_time Evaluation time for Uno's C-index
compute_cindex_both <- function(time, status, predictions, eval_time = 365.25) {
  # Harrell's C-index
  harrell_c <- tryCatch({
    survival::concordance(survival::Surv(time, status) ~ predictions)$concordance
  }, error = function(e) NA_real_)
  
  # Uno's C-index at specified time
  uno_c <- tryCatch({
    riskRegression::Score(
      object = list(predictions),
      formula = survival::Surv(time, status) ~ 1,
      data = data.frame(time = time, status = status),
      times = eval_time,
      summary = "risks"
    )$AUC$score$AUC[1]
  }, error = function(e) NA_real_)
  
  data.frame(
    harrell_cindex = harrell_c,
    uno_cindex = uno_c,
    eval_time = eval_time
  )
}

##' Model performance summary with confidence intervals
##' @param results List of model results with cindex values
##' @param alpha Confidence level (default 0.05 for 95% CI)
summarize_model_performance <- function(results, alpha = 0.05) {
  results %>%
    group_by(model) %>%
    summarise(
      n_splits = n(),
      mean_cindex = mean(cindex, na.rm = TRUE),
      sd_cindex = sd(cindex, na.rm = TRUE),
      se_cindex = sd_cindex / sqrt(n_splits),
      ci_lower = mean_cindex - qt(1 - alpha/2, n_splits - 1) * se_cindex,
      ci_upper = mean_cindex + qt(1 - alpha/2, n_splits - 1) * se_cindex,
      .groups = "drop"
    ) %>%
    arrange(desc(mean_cindex))
}