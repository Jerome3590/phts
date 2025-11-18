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
  # Build formula safely: prefer glue::glue if available, else fall back to paste0
  if (requireNamespace('glue', quietly = TRUE)) {
    formula <- as.formula(glue::glue("Surv({time}, {status}) ~ ."))
  } else {
    formula <- as.formula(paste0("Surv(", time, ", ", status, ") ~ ."))
  }
  
  if (!requireNamespace('survival', quietly = TRUE)) stop("Package 'survival' is required for safe_coxph. Please install it.")
  
  # ENHANCED LOGGING: Log initial data diagnostics
  predictor_vars <- setdiff(names(data), c(time, status))
  cat(sprintf("[CPH_INIT] Starting CPH model with %d observations, %d predictors\n", 
              nrow(data), length(predictor_vars)))
  cat(sprintf("[CPH_INIT] Events: %d (%.1f%%), Censored: %d (%.1f%%)\n", 
              sum(data[[status]]), 100 * mean(data[[status]]), 
              sum(1 - data[[status]]), 100 * (1 - mean(data[[status]]))))
  cat(sprintf("[CPH_INIT] Events per predictor ratio: %.2f (recommended: >10)\n", 
              sum(data[[status]]) / length(predictor_vars)))
  
  # Check for potential issues before fitting
  potential_issues <- character(0)
  
  # Check for variables with very low variance
  for (var in predictor_vars) {
    if (is.numeric(data[[var]])) {
      var_sd <- sd(data[[var]], na.rm = TRUE)
      if (is.finite(var_sd) && var_sd < 1e-10) {
        potential_issues <- c(potential_issues, sprintf("%s (zero variance)", var))
      }
    } else if (is.factor(data[[var]]) || is.character(data[[var]])) {
      var_table <- table(data[[var]], useNA = "ifany")
      if (length(var_table) == 1) {
        potential_issues <- c(potential_issues, sprintf("%s (single level)", var))
      } else if (any(var_table < 5)) {
        small_levels <- names(var_table)[var_table < 5]
        potential_issues <- c(potential_issues, sprintf("%s (small levels: %s)", var, paste(small_levels, collapse = ",")))
      }
    }
  }
  
  if (length(potential_issues) > 0) {
    cat(sprintf("[CPH_INIT] Potential issues detected in %d variables:\n", length(potential_issues)))
    for (issue in potential_issues) {
      cat(sprintf("[CPH_INIT] - %s\n", issue))
    }
  } else {
    cat("[CPH_INIT] No obvious data issues detected\n")
  }
  
  # ENHANCED: Check for CPH-specific split issues (tree models work, so focus on Cox-specific problems)
  n_events <- sum(data[[status]])
  n_predictors <- length(predictor_vars)
  event_rate <- mean(data[[status]])
  events_per_var <- n_events / n_predictors
  
  # CPH-specific criteria (more lenient than general ML since tree models work)
  min_events_per_var <- 5  # Lower threshold since tree models succeed
  min_event_rate <- 0.02   # Lower threshold since tree models succeed
  
  split_issues <- character(0)
  cox_specific_issues <- character(0)
  
  # Check basic statistical requirements
  if (events_per_var < min_events_per_var) {
    split_issues <- c(split_issues, sprintf("Low events/predictor ratio: %.2f (min: %d)", events_per_var, min_events_per_var))
  }
  if (event_rate < min_event_rate) {
    split_issues <- c(split_issues, sprintf("Low event rate: %.1f%% (min: %.1f%%)", event_rate * 100, min_event_rate * 100))
  }
  
  # Check for Cox-specific issues that tree models handle fine
  for (var in predictor_vars) {
    if (var %in% names(data)) {
      if (is.factor(data[[var]]) || is.character(data[[var]])) {
        # Check for perfect separation (Cox problem, tree models handle fine)
        cross_tab <- table(data[[var]], data[[status]], useNA = "ifany")
        if (any(rowSums(cross_tab == 0) > 0)) {
          separated_levels <- rownames(cross_tab)[rowSums(cross_tab == 0) > 0]
          cox_specific_issues <- c(cox_specific_issues, 
            sprintf("%s (separation in levels: %s)", var, paste(separated_levels, collapse = ",")))
        }
      }
    }
  }
  
  # Check for multicollinearity (Cox problem, tree models handle fine)
  numeric_vars <- predictor_vars[sapply(predictor_vars, function(v) is.numeric(data[[v]]))]
  if (length(numeric_vars) > 1) {
    tryCatch({
      # Remove variables with zero variance before correlation calculation
      numeric_data <- data[, numeric_vars, drop = FALSE]
      var_check <- apply(numeric_data, 2, function(x) var(x, na.rm = TRUE))
      non_zero_var_vars <- names(var_check)[var_check > 0]
      
      if (length(non_zero_var_vars) > 1) {
        cor_matrix <- cor(numeric_data[, non_zero_var_vars, drop = FALSE], use = "complete.obs")
      } else {
        cor_matrix <- matrix(1, nrow = 1, ncol = 1, dimnames = list(non_zero_var_vars, non_zero_var_vars))
      }
      high_cor_pairs <- which(abs(cor_matrix) > 0.99 & cor_matrix != 1, arr.ind = TRUE)
      if (nrow(high_cor_pairs) > 0) {
        for (i in 1:nrow(high_cor_pairs)) {
          var1 <- non_zero_var_vars[high_cor_pairs[i, 1]]
          var2 <- non_zero_var_vars[high_cor_pairs[i, 2]]
          cox_specific_issues <- c(cox_specific_issues, 
            sprintf("High correlation: %s ↔ %s (r=%.3f)", var1, var2, cor_matrix[high_cor_pairs[i, 1], high_cor_pairs[i, 2]]))
        }
      }
    }, error = function(e) NULL)
  }
  
  # Handle Cox-specific issues (since tree models work, focus on Cox problems)
  total_issues <- length(split_issues) + length(cox_specific_issues)
  
  if (total_issues > 0) {
    cat(sprintf("[CPH_COX_ISSUES] Cox-specific issues detected (%d total):\n", total_issues))
    
    # Log basic split issues
    for (issue in split_issues) {
      cat(sprintf("[CPH_COX_ISSUES] - %s\n", issue))
    }
    
    # Log Cox-specific issues (separation, multicollinearity)
    for (issue in cox_specific_issues) {
      cat(sprintf("[CPH_COX_ISSUES] - %s\n", issue))
    }
    
    # Strategy 1: Use penalized Cox regression (handles multicollinearity and some separation)
    use_penalized <- (events_per_var < 8) || (length(cox_specific_issues) > 0)
    
    if (use_penalized && requireNamespace("glmnet", quietly = TRUE)) {
      cat(sprintf("[CPH_PENALIZED] Using penalized Cox regression (Cox-specific issues: %d)\n", length(cox_specific_issues)))
      
      tryCatch({
        # Prepare data for glmnet (handles multicollinearity and separation better)
        predictor_data <- data[, predictor_vars, drop = FALSE]
        
        # Handle factor variables properly for glmnet
        factor_vars <- sapply(predictor_data, function(x) is.factor(x) || is.character(x))
        if (any(factor_vars)) {
          # Convert factors to model matrix (handles separation better than coxph)
          x_matrix <- model.matrix(~ . - 1, data = predictor_data)
        } else {
          x_matrix <- as.matrix(predictor_data)
        }
        
        y_surv <- survival::Surv(data[[time]], data[[status]])
        
        # Use elastic net (alpha=0.5) to handle both multicollinearity and variable selection
        cv_fit <- glmnet::cv.glmnet(x_matrix, y_surv, family = "cox", alpha = 0.5, 
                                   nfolds = min(5, max(3, nrow(data) %/% 20)))
        penalized_model <- glmnet::glmnet(x_matrix, y_surv, family = "cox", lambda = cv_fit$lambda.min)
        
        n_active <- sum(as.matrix(coef(penalized_model)) != 0)
        cat(sprintf("[CPH_PENALIZED] Penalized model fitted successfully\n"))
        cat(sprintf("[CPH_PENALIZED] Lambda: %.6f, Active coefficients: %d/%d\n", 
                    cv_fit$lambda.min, n_active, ncol(x_matrix)))
        
        # CRITICAL: Store training data structure for proper prediction
        # This is needed to ensure test data gets the same model matrix structure
        penalized_model$call <- call("penalized_coxph")
        penalized_model$training_data <- predictor_data
        penalized_model$predictor_vars <- predictor_vars
        penalized_model$factor_vars <- names(predictor_data)[factor_vars]
        penalized_model$data_info <- list(
          n_obs = nrow(data),
          n_events = n_events,
          n_predictors = n_predictors,
          n_active_coef = n_active,
          lambda = cv_fit$lambda.min,
          penalized = TRUE,
          cox_issues = cox_specific_issues,
          split_issues = split_issues
        )
        
        return(penalized_model)
      }, error = function(e) {
        cat(sprintf("[CPH_PENALIZED] Penalized fitting failed: %s\n", e$message))
        cat("[CPH_PENALIZED] Falling back to iterative variable dropping\n")
      })
    } else {
      cat("[CPH_FALLBACK] glmnet not available, using iterative variable dropping\n")
    }
  } else {
    cat("[CPH_INIT] No Cox-specific issues detected - proceeding with standard fitting\n")
  }
  
  cph_model <- survival::coxph(formula = formula, data = data, x = x)
  
  data_refit <- data
  
  # CRITICAL FIX: Add iteration limit to prevent infinite loops
  max_iterations <- 10
  iteration_count <- 0
  
  dropped_vars_log <- character(0)  # Track all dropped variables
  
  while ( any(is.na(cph_model$coefficients)) && iteration_count < max_iterations ) {
    iteration_count <- iteration_count + 1
    
    na_index <- which(is.na(cph_model$coefficients))
    to_drop <- names(cph_model$coefficients)[na_index]
    
    # ENHANCED LOGGING: Log detailed information about problematic variables
    cat(sprintf("[CPH_DEBUG] Iteration %d: Found %d variables with NA coefficients\n", 
                iteration_count, length(to_drop)))
    cat(sprintf("[CPH_DEBUG] Variables with NA coefficients: %s\n", 
                paste(to_drop, collapse = ", ")))
    
    # Log coefficient values for debugging
    coef_summary <- cph_model$coefficients
    na_coefs <- coef_summary[is.na(coef_summary)]
    finite_coefs <- coef_summary[is.finite(coef_summary)]
    
    cat(sprintf("[CPH_DEBUG] Total coefficients: %d, NA: %d, Finite: %d\n", 
                length(coef_summary), length(na_coefs), length(finite_coefs)))
    
    if (length(finite_coefs) > 0) {
      cat(sprintf("[CPH_DEBUG] Finite coefficient range: [%.4f, %.4f]\n", 
                  min(finite_coefs), max(finite_coefs)))
    }
    
    # Safety check: ensure we don't drop all variables
    remaining_vars <- setdiff(names(data_refit), c('time', 'status'))
    vars_to_drop <- intersect(to_drop, remaining_vars)
    
    if (length(vars_to_drop) == 0 || length(remaining_vars) <= length(vars_to_drop)) {
      # Can't drop any more variables safely
      warning(sprintf("CPH model has NA coefficients but cannot drop more variables safely. Remaining vars: %d, Vars to drop: %d", 
                     length(remaining_vars), length(vars_to_drop)))
      cat(sprintf("[CPH_DEBUG] Cannot drop more variables. Remaining: %s\n", 
                  paste(remaining_vars, collapse = ", ")))
      break
    }
    
    # Log what we're about to drop
    cat(sprintf("[CPH_DEBUG] Dropping %d variables: %s\n", 
                length(vars_to_drop), paste(vars_to_drop, collapse = ", ")))
    
    # Track dropped variables
    dropped_vars_log <- c(dropped_vars_log, vars_to_drop)
    
    # Log data diagnostics for problematic variables before dropping
    for (var in vars_to_drop) {
      if (var %in% names(data_refit)) {
        var_data <- data_refit[[var]]
        if (is.numeric(var_data)) {
          cat(sprintf("[CPH_DEBUG] Variable '%s' (numeric): n=%d, missing=%d, range=[%.4f, %.4f], unique=%d\n", 
                      var, length(var_data), sum(is.na(var_data)), 
                      min(var_data, na.rm = TRUE), max(var_data, na.rm = TRUE), 
                      length(unique(var_data[!is.na(var_data)]))))
        } else if (is.factor(var_data) || is.character(var_data)) {
          var_table <- table(var_data, useNA = "ifany")
          cat(sprintf("[CPH_DEBUG] Variable '%s' (categorical): n=%d, levels=%d\n", 
                      var, length(var_data), length(var_table)))
          cat(sprintf("[CPH_DEBUG] Level counts: %s\n", 
                      paste(paste(names(var_table), var_table, sep = "="), collapse = ", ")))
          
          # Check for separation with outcome
          if ('status' %in% names(data_refit)) {
            cross_tab <- table(var_data, data_refit$status, useNA = "ifany")
            if (any(rowSums(cross_tab == 0) > 0)) {
              cat(sprintf("[CPH_DEBUG] SEPARATION DETECTED in '%s':\n", var))
              print(cross_tab)
            }
          }
        }
      }
    }
    
    data_refit[, vars_to_drop] <- NULL
    
    # Rebuild formula with remaining variables
    remaining_vars_after_drop <- setdiff(names(data_refit), c('time', 'status'))
    cat(sprintf("[CPH_DEBUG] Variables remaining after drop: %d (%s)\n", 
                length(remaining_vars_after_drop), 
                paste(remaining_vars_after_drop, collapse = ", ")))
    
    if (length(remaining_vars_after_drop) == 0) {
      # No variables left - return null model
      warning("CPH model: All variables dropped due to NA coefficients")
      cat(sprintf("[CPH_DEBUG] All variables dropped. Total dropped: %s\n", 
                  paste(dropped_vars_log, collapse = ", ")))
      if (requireNamespace('survival', quietly = TRUE)) {
        return(survival::coxph(as.formula(paste0("Surv(", time, ", ", status, ") ~ 1")), data = data_refit, x = x))
      }
    }
    
    cph_model <- survival::coxph(formula = formula, data = data_refit, x = x)
    
    # Log success of refit
    new_na_count <- sum(is.na(cph_model$coefficients))
    cat(sprintf("[CPH_DEBUG] Refit complete. New NA coefficients: %d\n", new_na_count))
  }
  
  # Final summary logging
  if (length(dropped_vars_log) > 0) {
    cat(sprintf("[CPH_SUMMARY] Total variables dropped: %d\n", length(dropped_vars_log)))
    cat(sprintf("[CPH_SUMMARY] Dropped variables: %s\n", paste(dropped_vars_log, collapse = ", ")))
  }
  
  if (iteration_count >= max_iterations) {
    warning(sprintf("CPH model: Maximum iterations (%d) reached while handling NA coefficients. Dropped: %s", 
                   max_iterations, paste(dropped_vars_log, collapse = ", ")))
  }
  
  final_na_count <- sum(is.na(cph_model$coefficients))
  if (final_na_count > 0) {
    remaining_na_vars <- names(cph_model$coefficients)[is.na(cph_model$coefficients)]
    cat(sprintf("[CPH_WARNING] Final model still has %d NA coefficients: %s\n", 
                final_na_count, paste(remaining_na_vars, collapse = ", ")))
  } else {
    cat(sprintf("[CPH_SUCCESS] Final model converged with %d coefficients\n", 
                length(cph_model$coefficients)))
  }
  
  cph_model
  
}
