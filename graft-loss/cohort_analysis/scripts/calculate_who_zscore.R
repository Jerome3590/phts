# WHO Growth Curve Z-Score Calculations
# This function calculates WHO z-scores and percentiles for height and weight
# Based on WHO Child Growth Standards (0-5 years) and WHO Growth Reference (5-19 years)

# Note: This is a simplified implementation. For production use, consider using
# the 'zscorer' or 'childsds' R packages which provide comprehensive WHO calculations.

calculate_who_zscore <- function(age_months, sex, measurement, type = c("height", "weight")) {
  # age_months: age in months
  # sex: 1 = male, 2 = female (or "M"/"F")
  # measurement: height in cm or weight in kg
  # type: "height" or "weight"
  
  type <- match.arg(type)
  
  # Convert sex to numeric if needed
  if (is.character(sex) || is.factor(sex)) {
    sex <- ifelse(tolower(substr(as.character(sex), 1, 1)) == "m", 1, 2)
  }
  
  # Initialize result vectors
  z_score <- rep(NA_real_, length(age_months))
  percentile <- rep(NA_real_, length(age_months))
  
  # Separate by age group
  # WHO Child Growth Standards: 0-60 months (0-5 years)
  # WHO Growth Reference: 61-228 months (5-19 years)
  
  idx_under5 <- age_months >= 0 & age_months <= 60 & !is.na(age_months)
  idx_5to19 <- age_months > 60 & age_months <= 228 & !is.na(age_months)
  
  # For children under 5 years: Use WHO Child Growth Standards
  # Simplified LMS parameters (for demonstration - should use full WHO tables)
  if (any(idx_under5)) {
    # This is a placeholder - actual implementation would use WHO LMS tables
    # For now, return NA with a note that full implementation is needed
    z_score[idx_under5] <- NA_real_
    percentile[idx_under5] <- NA_real_
  }
  
  # For children 5-19 years: Use WHO Growth Reference
  if (any(idx_5to19)) {
    # This is a placeholder - actual implementation would use WHO LMS tables
    # For now, return NA with a note that full implementation is needed
    z_score[idx_5to19] <- NA_real_
    percentile[idx_5to19] <- NA_real_
  }
  
  # Convert z-scores to percentiles (if z-scores were calculated)
  if (any(!is.na(z_score))) {
    percentile[!is.na(z_score)] <- pnorm(z_score[!is.na(z_score)]) * 100
  }
  
  return(list(
    z_score = z_score,
    percentile = percentile
  ))
}

# Helper function to calculate WHO z-scores using external package if available
# This function attempts to use the 'zscorer' package if installed
calculate_who_zscore_with_package <- function(age_months, sex, measurement, type = c("height", "weight")) {
  type <- match.arg(type)
  
  # Check if zscorer package is available
  if (requireNamespace("zscorer", quietly = TRUE)) {
    # Use zscorer package
    if (type == "height") {
      result <- zscorer::getWGS(sex = sex, age = age_months / 12, height = measurement / 100)
      return(list(
        z_score = result$z,
        percentile = result$perc
      ))
    } else if (type == "weight") {
      result <- zscorer::getWGS(sex = sex, age = age_months / 12, weight = measurement)
      return(list(
        z_score = result$z,
        percentile = result$perc
      ))
    }
  }
  
  # Fallback to manual calculation (placeholder)
  return(calculate_who_zscore(age_months, sex, measurement, type))
}

# Main function to add WHO calculations to a dataset
add_who_calculations <- function(data, age_var = "age_txpl_months", sex_var = "sex", 
                                 height_var = "height_txpl", weight_var = "weight_txpl") {
  # Check if required variables exist
  required_vars <- c(age_var, sex_var, height_var, weight_var)
  missing_vars <- setdiff(required_vars, names(data))
  if (length(missing_vars) > 0) {
    warning("Missing required variables for WHO calculations: ", paste(missing_vars, collapse = ", "))
    return(data)
  }
  
  # Convert age to months if needed (assuming age is in years)
  if (!age_var %in% names(data)) {
    # Try to calculate age in months from other variables
    if ("age_txpl" %in% names(data)) {
      data[[age_var]] <- data$age_txpl * 12
    } else {
      warning("Cannot determine age in months for WHO calculations")
      return(data)
    }
  }
  
  # Calculate height-for-age z-scores and percentiles
  height_who <- calculate_who_zscore_with_package(
    age_months = data[[age_var]],
    sex = data[[sex_var]],
    measurement = data[[height_var]],
    type = "height"
  )
  
  # Calculate weight-for-age z-scores and percentiles
  weight_who <- calculate_who_zscore_with_package(
    age_months = data[[age_var]],
    sex = data[[sex_var]],
    measurement = data[[weight_var]],
    type = "weight"
  )
  
  # Add to dataset
  data$height_zscore_txpl <- height_who$z_score
  data$height_percentile_txpl <- height_who$percentile
  data$weight_zscore_txpl <- weight_who$z_score
  data$weight_percentile_txpl <- weight_who$percentile
  
  return(data)
}

