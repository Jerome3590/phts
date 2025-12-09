# Quick script to check if DONISCH and CPBYPASS variables exist in the dataset
# Run this separately before running the main analysis

library(here)
library(haven)
library(dplyr)
library(janitor)

cat("Loading data to check variables...\n")

# Load data
sas_path_local <- here("data", "phts_txpl_ml.sas7bdat")
sas_path_external <- here("graft-loss-parallel-processing", "data", "phts_txpl_ml.sas7bdat")
sas_path <- if (file.exists(sas_path_local)) sas_path_local else sas_path_external

if (!file.exists(sas_path)) {
  # Try graft-loss/data
  sas_path <- here("graft-loss", "data", "phts_txpl_ml.sas7bdat")
  if (!file.exists(sas_path)) {
    stop("Cannot find phts_txpl_ml.sas7bdat")
  }
}

phts_base <- haven::read_sas(sas_path) %>%
  filter(TXPL_YEAR >= 2010) %>%
  janitor::clean_names()

cat(sprintf("\nLoaded data: %d rows, %d columns\n", nrow(phts_base), ncol(phts_base)))

# Check for DONISCH and CPBYPASS variables
cat("\n=== Checking for Required Variables ===\n")
donisch_found <- "donisch" %in% names(phts_base)
cpbypass_found <- "cpbypass" %in% names(phts_base)

cat(sprintf("\nDONISCH found: %s\n", if (donisch_found) "YES" else "NO"))
if (donisch_found) {
  donisch_n <- sum(!is.na(phts_base$donisch))
  donisch_pct <- 100 * donisch_n / nrow(phts_base)
  cat(sprintf("  Non-missing values: %d (%.1f%%)\n", donisch_n, donisch_pct))
  if (donisch_n > 0) {
    cat(sprintf("  Range: %.1f - %.1f minutes (%.2f - %.2f hours)\n", 
                min(phts_base$donisch, na.rm = TRUE), 
                max(phts_base$donisch, na.rm = TRUE),
                min(phts_base$donisch, na.rm = TRUE) / 60,
                max(phts_base$donisch, na.rm = TRUE) / 60))
    cat(sprintf("  Median: %.1f minutes (%.2f hours)\n",
                median(phts_base$donisch, na.rm = TRUE),
                median(phts_base$donisch, na.rm = TRUE) / 60))
  }
} else {
  # Check for alternative names
  cat("  Checking for alternative names...\n")
  alt_names <- c("DONISCH", "donor_ischemic_time", "donor_isch_time", "donisch_time")
  found_alt <- NULL
  for (alt in alt_names) {
    if (alt %in% names(phts_base)) {
      found_alt <- alt
      break
    }
  }
  if (!is.null(found_alt)) {
    cat(sprintf("  ✓ Found alternative name: %s\n", found_alt))
  } else {
    cat("  ✗ DONISCH not found in dataset!\n")
    cat("  Available columns containing 'don' or 'isch':\n")
    matching_cols <- names(phts_base)[grepl("don|isch", names(phts_base), ignore.case = TRUE)]
    if (length(matching_cols) > 0) {
      cat(sprintf("    %s\n", paste(matching_cols, collapse = ", ")))
    } else {
      cat("    None found\n")
    }
  }
}

cat(sprintf("\nCPBYPASS found: %s\n", if (cpbypass_found) "YES" else "NO"))
if (cpbypass_found) {
  cpbypass_n <- sum(!is.na(phts_base$cpbypass))
  cpbypass_pct <- 100 * cpbypass_n / nrow(phts_base)
  cat(sprintf("  Non-missing values: %d (%.1f%%)\n", cpbypass_n, cpbypass_pct))
  if (cpbypass_n > 0) {
    cat(sprintf("  Range: %.1f - %.1f minutes (%.2f - %.2f hours)\n", 
                min(phts_base$cpbypass, na.rm = TRUE), 
                max(phts_base$cpbypass, na.rm = TRUE),
                min(phts_base$cpbypass, na.rm = TRUE) / 60,
                max(phts_base$cpbypass, na.rm = TRUE) / 60))
    cat(sprintf("  Median: %.1f minutes (%.2f hours)\n",
                median(phts_base$cpbypass, na.rm = TRUE),
                median(phts_base$cpbypass, na.rm = TRUE) / 60))
  }
} else {
  # Check for alternative names
  cat("  Checking for alternative names...\n")
  alt_names <- c("CPBYPASS", "cp_bypass", "cardiopulmonary_bypass", "bypass_time")
  found_alt <- NULL
  for (alt in alt_names) {
    if (alt %in% names(phts_base)) {
      found_alt <- alt
      break
    }
  }
  if (!is.null(found_alt)) {
    cat(sprintf("  ✓ Found alternative name: %s\n", found_alt))
  } else {
    cat("  ✗ CPBYPASS not found in dataset!\n")
    cat("  Available columns containing 'bypass' or 'cpb':\n")
    matching_cols <- names(phts_base)[grepl("bypass|cpb", names(phts_base), ignore.case = TRUE)]
    if (length(matching_cols) > 0) {
      cat(sprintf("    %s\n", paste(matching_cols, collapse = ", ")))
    } else {
      cat("    None found\n")
    }
  }
}

cat("\n========================================\n")
cat("Summary:\n")
cat(sprintf("  DONISCH available: %s\n", if (donisch_found) "YES ✓" else "NO ✗"))
cat(sprintf("  CPBYPASS available: %s\n", if (cpbypass_found) "YES ✓" else "NO ✗"))
cat("========================================\n")

