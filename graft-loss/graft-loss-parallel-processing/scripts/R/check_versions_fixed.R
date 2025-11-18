#!/usr/bin/env Rscript
# Check model library versions
# Usage: Rscript scripts/check_versions.R

# Load required libraries
library(here)

# Source the version checking functions
if (file.exists(here::here("scripts", "R", "check_model_versions.R"))) {
  source(here::here("scripts", "R", "check_model_versions.R"))
  
  cat("=== MODEL LIBRARY VERSION CHECK ===\n")
  cat(sprintf("Checking versions at: %s\n", Sys.time()))
  cat(sprintf("Working directory: %s\n", getwd()))
  cat("\n")
  
  # Get version information
  versions <- check_model_versions()
  
  # Print formatted version information
  print_model_versions(versions)
  
  # Check for compatibility issues
  cat("\n=== COMPATIBILITY CHECK ===\n")
  compatibility <- check_version_compatibility(versions)
  
  if (compatibility$critical_issues) {
    cat("❌ CRITICAL ISSUES DETECTED:\n")
    for (warning in compatibility$warnings) {
      cat(sprintf("  • %s\n", warning))
    }
    cat("\n📋 RECOMMENDATIONS:\n")
    for (rec in compatibility$recommendations) {
      cat(sprintf("  • %s\n", rec))
    }
  } else {
    cat("✅ All critical packages are compatible\n")
  }
  
  # Save version information
  output_dir <- here::here("logs", "versions")
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  }
  
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  
  # Save as text
  text_file <- file.path(output_dir, sprintf("model_versions_%s.txt", timestamp))
  save_model_versions(text_file, versions, format = "text")
  
  # Save as JSON if jsonlite is available
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    json_file <- file.path(output_dir, sprintf("model_versions_%s.json", timestamp))
    save_model_versions(json_file, versions, format = "json")
  }
  
  cat(sprintf("\n📁 Version information saved to: %s\n", output_dir))
  
} else {
  cat("ERROR: check_model_versions.R not found\n")
  cat("Please ensure the file exists at: R/check_model_versions.R\n")
  quit(status = 1)
}
