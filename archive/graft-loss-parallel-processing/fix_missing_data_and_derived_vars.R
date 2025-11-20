#!/usr/bin/env Rscript

# Fix missing data and derived variables for C-index calculation
# This script addresses the major issues found:
# 1. Missing derived variables (BMI, eGFR, PRA, Listing Year)
# 2. Missing median imputation in main pipeline
# 3. High missing data rates in key variables

library(here)
library(dplyr)

cat("=== FIXING MISSING DATA AND DERIVED VARIABLES ===\n")

# Load the data
data <- readRDS('model_data/phts_all.rds')
cat("Loaded data with", nrow(data), "observations\n")

# 1. Calculate missing derived variables
cat("\n=== CALCULATING DERIVED VARIABLES ===\n")

# BMI at Transplant (US formula: (weight_lbs / height_inches^2) * 703)
if (!"bmi_txpl" %in% names(data)) {
  cat("Calculating BMI at Transplant...\n")
  data$bmi_txpl <- (data$weight_txpl / (data$height_txpl^2)) * 703
  cat("BMI calculated for", sum(!is.na(data$bmi_txpl)), "observations\n")
}

# eGFR at Transplant (Pediatric Schwartz formula: 0.413 * height_cm / creatinine_mg_dL)
if (!"egfr_tx" %in% names(data)) {
  cat("Calculating eGFR at Transplant...\n")
  # Convert height from inches to cm (1 inch = 2.54 cm)
  height_cm <- data$height_txpl * 2.54
  data$egfr_tx <- 0.413 * height_cm / data$txcreat_r
  # Handle division by zero or negative creatinine
  data$egfr_tx[data$txcreat_r <= 0 | is.na(data$txcreat_r)] <- NA
  cat("eGFR calculated for", sum(!is.na(data$egfr_tx)), "observations\n")
}

# PRA at Listing (from lsfprat)
if (!"pra_listing" %in% names(data)) {
  cat("Calculating PRA at Listing...\n")
  data$pra_listing <- data$lsfprat
  cat("PRA calculated for", sum(!is.na(data$pra_listing)), "observations\n")
}

# Listing Year (from age difference: txpl_year - (age_txpl - age_listing))
if (!"listing_year" %in% names(data)) {
  cat("Calculating Listing Year...\n")
  age_diff <- data$age_txpl - data$age_listing
  data$listing_year <- data$txpl_year - age_diff
  # Fallback: txpl_year - 1 if age variables unavailable
  data$listing_year[is.na(age_diff)] <- data$txpl_year[is.na(age_diff)] - 1
  cat("Listing Year calculated for", sum(!is.na(data$listing_year)), "observations\n")
}

# 2. Apply median imputation to missing data
cat("\n=== APPLYING MEDIAN IMPUTATION ===\n")

# Get the 15 Wisotzkey variables
wisotzkey_vars <- c('prim_dx', 'tx_mcsd', 'chd_sv', 'hxsurg', 'txsa_r', 'txbun_r', 
                   'txecmo', 'txpl_year', 'weight_txpl', 'txalt', 'bmi_txpl', 
                   'pra_listing', 'egfr_tx', 'hxmed', 'listing_year')

# Check which variables exist
available_vars <- wisotzkey_vars[wisotzkey_vars %in% names(data)]
missing_vars <- setdiff(wisotzkey_vars, names(data))

cat("Available Wisotzkey variables:", length(available_vars), "\n")
cat("Missing Wisotzkey variables:", length(missing_vars), "\n")
if (length(missing_vars) > 0) {
  cat("Missing:", paste(missing_vars, collapse = ", "), "\n")
}

# Apply median imputation to available variables
for (var in available_vars) {
  missing_count <- sum(is.na(data[[var]]))
  if (missing_count > 0) {
    cat(sprintf("Imputing %s: %d missing values (%.1f%%)\n", 
                var, missing_count, 100 * missing_count / nrow(data)))
    
    if (is.numeric(data[[var]])) {
      # Numeric variables: impute median
      data[[var]][is.na(data[[var]])] <- median(data[[var]], na.rm = TRUE)
    } else {
      # Categorical variables: impute mode (most frequent value)
      mode_val <- names(sort(table(data[[var]]), decreasing = TRUE))[1]
      data[[var]][is.na(data[[var]])] <- mode_val
    }
  }
}

# 3. Verify the fix
cat("\n=== VERIFICATION ===\n")
cat("Final missing data summary:\n")
for (var in available_vars) {
  missing_count <- sum(is.na(data[[var]]))
  missing_pct <- round(100 * missing_count / nrow(data), 2)
  cat(sprintf("%s: %d missing (%.1f%%)\n", var, missing_count, missing_pct))
}

# 4. Save the fixed data
cat("\n=== SAVING FIXED DATA ===\n")
saveRDS(data, 'model_data/phts_all_fixed.rds')
cat("Fixed data saved to model_data/phts_all_fixed.rds\n")

# 5. Create a summary
cat("\n=== SUMMARY ===\n")
cat("Original data:", nrow(data), "observations\n")
cat("Variables with missing data fixed:", length(available_vars), "\n")
cat("Derived variables calculated: BMI, eGFR, PRA, Listing Year\n")
cat("Missing data imputed with medians/modes\n")
cat("Ready for C-index calculation!\n")
