# ===================
# FALLBACK ERROR HANDLING MODULE
# ===================
# This module handles fallback scenarios when the main model fitting fails.

#' Handle fallback model fitting when main process fails
#' @param error_message The error message from the main process
#' @return List with success status and results
handle_fallback_fitting <- function(error_message) {
  tryCatch({
    cat(sprintf("[ERROR] Failed to fit final models: %s\n", error_message))
    if (grepl("timeout", error_message, ignore.case = TRUE)) {
      cat("[ERROR] Model fitting timed out - likely too large for available resources\n")
    }
    cat("[ERROR] Attempting fallback: fitting simpler RSF model only...\n")
    
    # Simple fallback - just try to fit RSF without all the complex duplicate code
    tryCatch({
      cat("[Progress] Fitting fallback RSF model...\n")
      flush.console()
      
      # Load final_data from step 03
      final_data_path <- here::here('model_data', 'final_data.rds')
      if (file.exists(final_data_path)) {
        final_data <- readRDS(final_data_path)
        cat(sprintf("[DEBUG] Loaded final_data: %d rows, %d cols\n", nrow(final_data), ncol(final_data)))
        
        # Use simple hardcoded features for fallback
        # NOTE: tx_mcsd has underscore - derived column created by clean_phts()
        fallback_vars <- c("prim_dx", "tx_mcsd", "chd_sv", "hxsurg", "txsa_r", "txecmo")
        available_vars <- intersect(fallback_vars, colnames(final_data))
        
        if (length(available_vars) > 0) {
          cat(sprintf("[Progress] Using %d fallback variables for RSF\n", length(available_vars)))
          
          # Simple RSF fitting without parallel processing
          fallback_rsf <- fit_rsf(trn = final_data, vars = available_vars, use_parallel = FALSE)
          
          # Save RSF as both the RSF model and as final_model for compatibility
          cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
          rsf_dir <- here::here('models', cohort_name)
          dir.create(rsf_dir, showWarnings = FALSE, recursive = TRUE)
          
          rsf_path <- file.path(rsf_dir, 'model_rsf.rds')
          saveRDS(fallback_rsf, rsf_path)
          final_path <- file.path(rsf_dir, 'final_model.rds')
          saveRDS(fallback_rsf, final_path)
          
          if (file.exists(rsf_path) && file.exists(final_path)) {
            cat("[Progress] ✓ Fallback successful: RSF model saved as final_model.rds\n")
            return(list(
              success = TRUE,
              results = list(RSF = list(
                model_name = "RSF",
                model_path = rsf_path,
                success = TRUE,
                fallback = TRUE
              )),
              message = "Fallback RSF model fitted successfully"
            ))
          } else {
            cat("[ERROR] ✗ Fallback also failed - Step 05 will fail\n")
            return(list(
              success = FALSE,
              error = "Failed to save fallback RSF model"
            ))
          }
        } else {
          cat("[ERROR] No fallback variables available\n")
          return(list(
            success = FALSE,
            error = "No fallback variables available"
          ))
        }
      } else {
        cat("[ERROR] final_data.rds not found for fallback\n")
        return(list(
          success = FALSE,
          error = "final_data.rds not found for fallback"
        ))
      }
    }, error = function(e2) {
      cat(sprintf("[ERROR] RSF fallback also failed: %s\n", conditionMessage(e2)))
      cat("[ERROR] No models saved - Step 05 will fail\n")
      return(list(
        success = FALSE,
        error = paste("RSF fallback failed:", conditionMessage(e2))
      ))
    })
    
  }, error = function(e) {
    cat(sprintf("[ERROR] Fallback handling failed: %s\n", conditionMessage(e)))
    return(list(
      success = FALSE,
      error = paste("Fallback handling failed:", conditionMessage(e))
    ))
  })
}

#' Handle minimal model creation as last resort
#' @param final_data The final dataset
#' @param model_vars The model variables
#' @return List with success status and results
create_minimal_model <- function(final_data, model_vars) {
  tryCatch({
    cat("[WARNING] Creating minimal dummy model to allow Step 05 to run...\n")
    
    # Create a very simple survival model with minimal data
    minimal_data <- final_data[sample(nrow(final_data), min(1000, nrow(final_data))), ]
    minimal_vars <- head(model_vars, 5)  # Use only first 5 variables
    
    cat(sprintf("[Progress] Fitting minimal model: %d rows, %d vars\n", nrow(minimal_data), length(minimal_vars)))
    cat("[Progress] Configuring parallel processing for minimal model...\n")
    
    # Simple RSF fitting without parallel processing for minimal model
    minimal_model <- fit_rsf(trn = minimal_data, vars = minimal_vars, use_parallel = FALSE)
    
    # Save minimal model
    cohort_name <- Sys.getenv('DATASET_COHORT', unset = 'unknown')
    final_dir <- here::here('models', cohort_name)
    dir.create(final_dir, showWarnings = FALSE, recursive = TRUE)
    final_path <- file.path(final_dir, 'final_model.rds')
    saveRDS(minimal_model, final_path)
    
    if (file.exists(final_path)) {
      cat("[WARNING] ✓ Minimal model saved - Step 05 can proceed with limited functionality\n")
      return(list(
        success = TRUE,
        results = list(RSF = list(
          model_name = "RSF",
          model_path = final_path,
          success = TRUE,
          minimal = TRUE
        )),
        message = "Minimal RSF model fitted successfully"
      ))
    } else {
      cat("[ERROR] ✗ Even minimal model failed - Step 05 will fail\n")
      return(list(
        success = FALSE,
        error = "Failed to save minimal model"
      ))
    }
    
  }, error = function(e) {
    cat(sprintf("[ERROR] Even minimal model failed: %s\n", conditionMessage(e)))
    cat("[ERROR] No models saved - Step 05 will fail\n")
    return(list(
      success = FALSE,
      error = paste("Minimal model failed:", conditionMessage(e))
    ))
  })
}

#' Comprehensive fallback strategy
#' @param error_message The error message from the main process
#' @param final_data Optional final data if available
#' @param model_vars Optional model variables if available
#' @return List with success status and results
comprehensive_fallback <- function(error_message, final_data = NULL, model_vars = NULL) {
  # Try simple fallback first
  fallback_result <- handle_fallback_fitting(error_message)
  
  if (fallback_result$success) {
    return(fallback_result)
  }
  
  # If simple fallback fails and we have data, try minimal model
  if (!is.null(final_data) && !is.null(model_vars)) {
    minimal_result <- create_minimal_model(final_data, model_vars)
    if (minimal_result$success) {
      return(minimal_result)
    }
  }
  
  # If all fallbacks fail
  return(list(
    success = FALSE,
    error = "All fallback strategies failed",
    details = list(
      simple_fallback = fallback_result,
      minimal_model = if (!is.null(final_data) && !is.null(model_vars)) minimal_result else "Not attempted"
    )
  ))
}
