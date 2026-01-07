#!/usr/bin/env Rscript

# ============================================================================
# Quick Runner Script for Calculator Models
# ============================================================================
# This script provides a simple interface to run calculator models
# Usage: Rscript run_calculator.R [CHD|Combined|Myocardio|All]
# ============================================================================

library(here)

# Source the main calculator script
source(here("graft-loss", "cohort_analysis", "calculator", "calculator_models.R"))

# Get command line argument
args <- commandArgs(trailingOnly = TRUE)
cohort_to_run <- if (length(args) > 0) args[1] else "All"

cat("========================================\n")
cat("Calculator Models Runner\n")
cat("========================================\n")
cat(sprintf("Cohort to run: %s\n", cohort_to_run))
cat("========================================\n\n")

# Modify main function to run specific cohort
if (cohort_to_run %in% c("CHD", "Combined", "Myocardio")) {
  # Run specific cohort
  cat(sprintf("Running %s model only...\n\n", cohort_to_run))
  
  # Set up parallel processing
  n_workers <- max(1, parallel::detectCores() - 2)
  plan(multisession, workers = n_workers)
  cat(sprintf("Using %d workers for parallel processing\n", n_workers))
  
  # Load data
  cat("Loading PHTS data...\n")
  sas_path_local <- here("data", "phts_txpl_ml.sas7bdat")
  sas_path_external <- here("graft-loss-parallel-processing", "data", "phts_txpl_ml.sas7bdat")
  sas_path_graft_loss <- here("graft-loss", "data", "phts_txpl_ml.sas7bdat")
  
  sas_path <- NULL
  for (path in c(sas_path_local, sas_path_external, sas_path_graft_loss)) {
    if (file.exists(path)) {
      sas_path <- path
      break
    }
  }
  
  if (is.null(sas_path)) {
    stop("Cannot find phts_txpl_ml.sas7bdat in any location")
  }
  
  cat("Loading data from:", sas_path, "\n")
  
  # Load and prepare data
  tx <- haven::read_sas(sas_path) %>%
    filter(TXPL_YEAR >= 2010) %>%
    janitor::clean_names() %>%
    mutate(
      ev_time = pmin(int_dead, int_graft_loss, na.rm = TRUE),
      ev_type = pmax(dtx_patient, graft_loss, na.rm = TRUE)
    ) %>%
    fix_non_positive_times(time_col = "ev_time", status_col = "ev_type")
  
  # Map prim_dx to primary_etiology if needed
  if (!"primary_etiology" %in% names(tx) && "prim_dx" %in% names(tx)) {
    tx <- tx %>% mutate(primary_etiology = prim_dx)
  }
  
  # Define cohort
  if (cohort_to_run == "CHD") {
    cohort_data <- tx %>% filter(primary_etiology == "Congenital HD")
  } else if (cohort_to_run == "Combined") {
    cohort_data <- tx
  } else if (cohort_to_run == "Myocardio") {
    cohort_data <- tx %>% filter(primary_etiology %in% c("Cardiomyopathy", "Myocarditis"))
  }
  
  # Run MC-CV
  result <- run_mc_cv_calculator(cohort_data, cohort_to_run, cohort_to_run)
  
  # Save results
  output_dir <- here("graft-loss", "cohort_analysis", "calculator", "outputs")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  write_csv(result$summary, file.path(output_dir, sprintf("calculator_%s_summary.csv", cohort_to_run)))
  cat(sprintf("\n✓ Saved summary to calculator_%s_summary.csv\n", cohort_to_run))
  
  # Save feature importance
  for (model_name in names(result$importance)) {
    imp_df <- tibble(
      feature = names(result$importance[[model_name]]),
      importance = as.numeric(result$importance[[model_name]]),
      cohort = cohort_to_run,
      model = model_name
    ) %>%
      arrange(desc(importance))
    
    write_csv(imp_df, file.path(output_dir, sprintf("importance_%s_%s.csv", cohort_to_run, model_name)))
  }
  
  cat("✓ Saved feature importance files\n")
  
  # Print summary
  cat("\n========================================\n")
  cat(sprintf("Summary Results for %s\n", cohort_to_run))
  cat("========================================\n")
  print(result$summary)
  
  # Identify best model
  best_model <- result$summary %>%
    arrange(desc(AUC_Mean)) %>%
    slice(1)
  
  cat("\n========================================\n")
  cat("Best Model\n")
  cat("========================================\n")
  print(best_model)
  
  plan(sequential)
  
} else {
  # Run all cohorts using main function
  main()
}

cat("\n✓ Analysis complete!\n")
