#!/usr/bin/env Rscript

# 01_prepare_data.R
# Simplified version of data preparation for notebook execution

# Source the main setup
source("pipeline/00_setup.R")

# Set up logging
log_file <- switch(Sys.getenv("DATASET_COHORT", unset = ""),
  original = "logs/orch_bg_original_study.log",
  full_with_covid = "logs/orch_bg_full_with_covid.log", 
  full_without_covid = "logs/orch_bg_full_without_covid.log",
  "logs/orch_bg_unknown.log"
)

# Create logs directory if it doesn't exist
dir.create("logs", showWarnings = FALSE, recursive = TRUE)

# Note: Logging is managed by run_pipeline.R orchestrator
# Individual pipeline scripts should not set up their own sink/on.exit handlers
# to avoid conflicts with the parent script's logging management

cat("=== Data Preparation (Simple) ===\n")
cat("Timestamp:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Cohort:", Sys.getenv("DATASET_COHORT", unset = "unknown"), "\n")
cat("Log file:", log_file, "\n\n")

# Simple data preparation using existing clean_phts() function
# This avoids the SAS parsing issues by using the already-working data cleaning pipeline

cat("[01_prepare_data.R] Starting simple data preparation using clean_phts()\n")

# Use the existing clean_phts() function instead of reading raw SAS
min_txpl_year <- 2010
predict_horizon <- 1

cat("[01_prepare_data.R] Calling clean_phts() function...\n")

# Ensure rlang is loaded for enquo() function
if (!requireNamespace("rlang", quietly = TRUE)) {
  cat("[01_prepare_data.R] Loading rlang package...\n")
  library(rlang)
}

# Try a different approach - pass the column names directly as symbols
# This should work with enquo() in the clean_phts function
cat("[01_prepare_data.R] Using column names: int_graft_loss, graft_loss\n")

# Create a simple wrapper that avoids the enquo issue
phts_all <- tryCatch({
  clean_phts(
    min_txpl_year = min_txpl_year,
    predict_horizon = predict_horizon,
    # Pass column names as strings to avoid name-capture issues
    time = "int_graft_loss",
    status = "graft_loss",
    case = 'snake',
    set_to_na = c("", "unknown", "missing")
  )
}, error = function(e) {
  cat("[01_prepare_data.R] Error with clean_phts():", e$message, "\n")
  cat("[01_prepare_data.R] Trying alternative approach...\n")
  # Dump traceback and session info to the log to aid debugging
  cat("[01_prepare_data.R] Traceback:\n")
  traceback()
  cat("[01_prepare_data.R] sessionInfo:\n")
  print(sessionInfo())
  
  # Alternative: Read the data directly and process it manually
  sas_path_local <- here('data', 'transplant.sas7bdat')
  sas_path_external <- here('..', 'data', 'transplant.sas7bdat')
  sas_path <- if (file.exists(sas_path_local)) sas_path_local else sas_path_external
  
  cat("[01_prepare_data.R] Reading SAS file directly from:", sas_path, "\n")
  
  if (!file.exists(sas_path)) {
    stop("SAS file not found at: ", sas_path)
  }
  
  # Read and process data manually
  data <- haven::read_sas(sas_path)
  cat("[01_prepare_data.R] Successfully read SAS file:", nrow(data), "rows,", ncol(data), "columns\n")
  
  # Basic processing
  data %>%
    filter(TXPL_YEAR >= min_txpl_year) %>%
    janitor::clean_names() %>%
    rename(
      outcome_int_graft_loss = int_graft_loss,
      outcome_graft_loss = graft_loss,
      time = int_graft_loss,
      status = graft_loss
    ) %>%
    mutate(
      ID = 1:n(),
      across(where(is.character), as.factor)
    )
})

cat("[01_prepare_data.R] clean_phts() completed successfully\n")
cat("[01_prepare_data.R] phts_all dimensions:", dim(phts_all), "\n")
cat("[01_prepare_data.R] phts_all column names:", paste(colnames(phts_all), collapse = ", "), "\n")

# Define the 15 Wisotzkey variables (using the cleaned column names after clean_names())
# NOTE: tx_mcsd has underscore - this is the derived column created by clean_phts()
wisotzkey_features <- c(
  "prim_dx",       # Primary Etiology
  "tx_mcsd",       # MCSD at Transplant (with underscore - derived column!)
  "chd_sv",        # Single Ventricle CHD
  "hxsurg",        # Surgeries Prior to Listing
  "txsa_r",        # Serum Albumin at Transplant
  "txbun_r",       # BUN at Transplant
  "txecmo",        # ECMO at Transplant
  "txpl_year",     # Transplant Year
  "weight_txpl",   # Weight at Transplant
  "txalt",         # ALT at Transplant
  "hxmed",         # Medical History
  "age_txpl",      # Age at Transplant
  "height_txpl",   # Height at Transplant
  "txcreat_r",     # Creatinine at Transplant
  "age_listing"    # Age at Listing
)

# Check which Wisotzkey features are available
available_features <- intersect(wisotzkey_features, colnames(phts_all))
missing_features <- setdiff(wisotzkey_features, colnames(phts_all))

cat("[01_prepare_data.R] Available Wisotzkey features:", length(available_features), "\n")
cat("[01_prepare_data.R] Available features:", paste(available_features, collapse = ", "), "\n")

if (length(missing_features) > 0) {
  cat("[01_prepare_data.R] Missing features:", paste(missing_features, collapse = ", "), "\n")
}

# Create derived variables that might be missing
cat("[01_prepare_data.R] Creating derived variables...\n")

# BMI at transplant (if not already present)
# NOTE: Using US formula with 703 factor (weight in lbs, height in inches)
if (!"bmi_txpl" %in% colnames(phts_all) && "weight_txpl" %in% colnames(phts_all) && "height_txpl" %in% colnames(phts_all)) {
  phts_all$bmi_txpl <- (phts_all$weight_txpl / (phts_all$height_txpl^2)) * 703
  cat("[01_prepare_data.R] Created bmi_txpl (US formula: weight_lbs / height_in^2 * 703)\n")
}

# eGFR at transplant (if not already present)
if (!"egfr_tx" %in% colnames(phts_all) && "txcreat_r" %in% colnames(phts_all) && "age_txpl" %in% colnames(phts_all)) {
  # Simple eGFR calculation (Schwartz formula for pediatrics)
  # Handle division by zero and very low creatinine values
  phts_all$egfr_tx <- ifelse(
    phts_all$txcreat_r <= 0 | is.na(phts_all$txcreat_r), 
    NA,  # Set to NA if creatinine is 0 or missing
    0.413 * phts_all$height_txpl / phts_all$txcreat_r
  )
  cat("[01_prepare_data.R] Created egfr_tx (handled division by zero)\n")
}

# Listing year (if not already present)
# Calculate from transplant year and age difference (per phts_eda.qmd reference)
if (!"listing_year" %in% colnames(phts_all) && "txpl_year" %in% colnames(phts_all) && "age_txpl" %in% colnames(phts_all) && "age_listing" %in% colnames(phts_all)) {
  phts_all$listing_year <- as.integer(floor(phts_all$txpl_year - (phts_all$age_txpl - phts_all$age_listing)))
  cat("[01_prepare_data.R] Created listing_year from txpl_year and age difference\n")
} else if (!"listing_year" %in% colnames(phts_all) && "txpl_year" %in% colnames(phts_all)) {
  # Fallback: assume listing year is transplant year minus 1
  phts_all$listing_year <- phts_all$txpl_year - 1
  cat("[01_prepare_data.R] Created listing_year (fallback: txpl_year - 1)\n")
}

# PRA at listing (if not already present)
# Using lsfprat (PRA T-cell at listing) per Wisotzkey paper
if (!"pra_listing" %in% colnames(phts_all) && "lsfprat" %in% colnames(phts_all)) {
  phts_all$pra_listing <- phts_all$lsfprat
  cat("[01_prepare_data.R] Created pra_listing from lsfprat (PRA T-cell at listing)\n")
}

# Select the final 15 Wisotzkey features plus time, status, and ID
final_features <- c(available_features, "bmi_txpl", "egfr_tx", "listing_year", "pra_listing")
final_features <- intersect(final_features, colnames(phts_all))

# Add time, status, and ID
required_cols <- c("time", "status", "ID")
final_cols <- c(final_features, required_cols)

# Select only the columns we need
phts_simple <- phts_all[, final_cols, drop = FALSE]

cat("[01_prepare_data.R] Final data dimensions:", dim(phts_simple), "\n")
cat("[01_prepare_data.R] Final column names:", paste(colnames(phts_simple), collapse = ", "), "\n")

# Check that time and status are properly formatted
cat("[01_prepare_data.R] time class:", class(phts_simple$time), "\n")
cat("[01_prepare_data.R] status class:", class(phts_simple$status), "\n")
cat("[01_prepare_data.R] time first 5 values:", paste(head(phts_simple$time, 5), collapse = ", "), "\n")
cat("[01_prepare_data.R] status first 5 values:", paste(head(phts_simple$status, 5), collapse = ", "), "\n")

# Save the simplified dataset in dual format (RDS + CSV)
# Dual format is critical for:
# 1. RDS: Fast R-native serialization for ORSF/XGB/CPH models
# 2. CSV: Required for CatBoost compatibility (CatBoost Python interface requires CSV)
output_path_rds <- here("model_data", "phts_simple.rds")
output_path_csv <- here("model_data", "phts_simple.csv")

# Save RDS for R-native models (ORSF, XGB, CPH)
saveRDS(phts_simple, output_path_rds)
cat("[01_prepare_data.R] Saved RDS to:", output_path_rds, "\n")

# Save CSV for CatBoost compatibility (CatBoost requires CSV format)
write.csv(phts_simple, output_path_csv, row.names = FALSE)
cat("[01_prepare_data.R] Saved CSV to:", output_path_csv, "\n")

# Create and save labels.rds (required by 07_generate_outputs.R)
cat("[01_prepare_data.R] Creating labels.rds...\n")
labels <- make_labels(colname_variable = 'variable', colname_label = 'label')
labels_path <- here("model_data", "labels.rds")
saveRDS(labels, labels_path)
cat("[01_prepare_data.R] Saved labels to:", labels_path, "\n")

cat("[01_prepare_data.R] Simple data preparation completed successfully\n")

cat("\n=== Data Preparation Complete ===\n")
cat("Finished at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")

