# Calculate Derived Features for Cohort Analysis
# This script adds eGFR, BMI, and WHO growth curve calculations to the data preparation pipeline

calculate_derived_features <- function(data) {
  # ============================================================================
  # CALCULATED VARIABLES: eGFR, BMI, and WHO Growth Curve Calculations
  # ============================================================================
  
  # Calculate eGFR using Schwartz formula (if components available)
  if ("height_txpl" %in% names(data) && "txcreat_r" %in% names(data)) {
    data <- data %>%
      mutate(
        egfr_tx = ifelse(
          !is.na(height_txpl) & !is.na(txcreat_r) & txcreat_r > 0,
          0.413 * height_txpl / txcreat_r,
          egfr_tx  # Keep existing value if calculation not possible
        )
      )
    cat("→ Calculated egfr_tx using Schwartz formula\n")
  }
  
  # Calculate BMI (if components available)
  if ("weight_txpl" %in% names(data) && "height_txpl" %in% names(data)) {
    data <- data %>%
      mutate(
        bmi_txpl = ifelse(
          !is.na(weight_txpl) & !is.na(height_txpl) & height_txpl > 0,
          (weight_txpl / (height_txpl^2)) * 703,
          bmi_txpl  # Keep existing value if calculation not possible
        )
      )
    cat("→ Calculated bmi_txpl\n")
  }
  
  # Calculate WHO growth curve z-scores and percentiles (if components available)
  # Source the WHO calculation helper function
  who_script <- here("scripts", "calculate_who_zscore.R")
  if (file.exists(who_script)) {
    source(who_script)
    
    # Check if we have required variables for WHO calculations
    # Need: age (in months), sex, height, weight
    age_months_var <- NULL
    if ("age_txpl_months" %in% names(data)) {
      age_months_var <- "age_txpl_months"
    } else if ("age_txpl" %in% names(data)) {
      # Convert age from years to months
      data$age_txpl_months <- data$age_txpl * 12
      age_months_var <- "age_txpl_months"
    }
    
    sex_var <- NULL
    if ("sex" %in% names(data)) {
      sex_var <- "sex"
    } else if ("rsex" %in% names(data)) {
      sex_var <- "rsex"
    }
    
    if (!is.null(age_months_var) && !is.null(sex_var) && 
        "height_txpl" %in% names(data) && "weight_txpl" %in% names(data)) {
      tryCatch({
        data <- add_who_calculations(
          data,
          age_var = age_months_var,
          sex_var = sex_var,
          height_var = "height_txpl",
          weight_var = "weight_txpl"
        )
        cat("→ Calculated WHO growth curve z-scores and percentiles\n")
      }, error = function(e) {
        warning("Failed to calculate WHO z-scores: ", e$message)
      })
    } else {
      cat("→ WHO calculations skipped (missing required variables: age, sex, height, or weight)\n")
    }
  } else {
    cat("→ WHO calculation script not found, skipping WHO calculations\n")
  }
  
  return(data)
}

