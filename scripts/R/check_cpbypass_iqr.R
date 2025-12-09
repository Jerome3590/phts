# Script to check CPBYPASS median and IQR statistics by period
# This replicates what will be calculated in the main analysis

library(here)
library(haven)
library(dplyr)
library(janitor)

cat("Loading data to calculate CPBYPASS statistics...\n")

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
  janitor::clean_names() %>%
  rename(
    outcome_int_graft_loss = int_graft_loss,
    outcome_graft_loss = graft_loss
  ) %>%
  mutate(
    ID = 1:n(),
    across(.cols = where(is.character), ~ ifelse(.x %in% c("", "unknown", "missing"), NA_character_, .x)),
    across(.cols = where(is.character), as.factor),
    tx_mcsd = if ('txnomcsd' %in% names(.)) {
      if_else(txnomcsd == 'yes', 0, 1)
    } else if ('txmcsd' %in% names(.)) {
      txmcsd
    } else {
      NA_real_
    }
  )

cat(sprintf("Loaded data: %d rows, %d columns\n", nrow(phts_base), ncol(phts_base)))

# Define time periods
periods <- list()
periods$original <- phts_base %>% filter(txpl_year >= 2010 & txpl_year <= 2019)
periods$full <- phts_base %>% filter(txpl_year >= 2010)
periods$full_no_covid <- phts_base %>% filter(txpl_year >= 2010 & !(txpl_year >= 2020 & txpl_year <= 2023))

# Calculate CPBYPASS statistics for each period
cat("\n=== CPBYPASS Statistics by Period ===\n\n")

for (period_name in names(periods)) {
  period_data <- periods[[period_name]]
  
  if ("cpbypass" %in% names(period_data)) {
    cpbypass_data <- period_data$cpbypass[!is.na(period_data$cpbypass)]
    
    if (length(cpbypass_data) > 0) {
      cpbypass_median <- median(cpbypass_data)
      cpbypass_q1 <- quantile(cpbypass_data, 0.25, na.rm = TRUE)
      cpbypass_q3 <- quantile(cpbypass_data, 0.75, na.rm = TRUE)
      cpbypass_iqr <- cpbypass_q3 - cpbypass_q1
      cpbypass_mean <- mean(cpbypass_data)
      cpbypass_sd <- sd(cpbypass_data)
      
      cat(sprintf("=== CPBYPASS Statistics (%s) ===\n", period_name))
      cat(sprintf("Period: %s\n", period_name))
      cat(sprintf("Total N: %d\n", nrow(period_data)))
      cat(sprintf("Non-missing CPBYPASS: %d (%.1f%%)\n", length(cpbypass_data), 
                  100 * length(cpbypass_data) / nrow(period_data)))
      cat(sprintf("\nDescriptive Statistics:\n"))
      cat(sprintf("  Mean: %.2f minutes (%.2f hours)\n", cpbypass_mean, cpbypass_mean / 60))
      cat(sprintf("  SD: %.2f minutes (%.2f hours)\n", cpbypass_sd, cpbypass_sd / 60))
      cat(sprintf("  Median: %.2f minutes (%.2f hours)\n", cpbypass_median, cpbypass_median / 60))
      cat(sprintf("  Q1 (25th percentile): %.2f minutes (%.2f hours)\n", cpbypass_q1, cpbypass_q1 / 60))
      cat(sprintf("  Q3 (75th percentile): %.2f minutes (%.2f hours)\n", cpbypass_q3, cpbypass_q3 / 60))
      cat(sprintf("  IQR Range: %.2f minutes (%.2f hours)\n", cpbypass_iqr, cpbypass_iqr / 60))
      cat(sprintf("  Min: %.2f minutes (%.2f hours)\n", min(cpbypass_data), min(cpbypass_data) / 60))
      cat(sprintf("  Max: %.2f minutes (%.2f hours)\n", max(cpbypass_data), max(cpbypass_data) / 60))
      cat("========================================\n\n")
    } else {
      cat(sprintf("=== CPBYPASS Statistics (%s) ===\n", period_name))
      cat(sprintf("No non-missing CPBYPASS values found\n"))
      cat("========================================\n\n")
    }
  } else {
    cat(sprintf("=== CPBYPASS Statistics (%s) ===\n", period_name))
    cat(sprintf("CPBYPASS variable not found in dataset\n"))
    cat("========================================\n\n")
  }
}

# Overall summary
cat("\n=== Overall CPBYPASS Summary ===\n")
if ("cpbypass" %in% names(phts_base)) {
  cpbypass_all <- phts_base$cpbypass[!is.na(phts_base$cpbypass)]
  if (length(cpbypass_all) > 0) {
    cat(sprintf("Overall Median: %.2f minutes (%.2f hours)\n", 
                median(cpbypass_all), median(cpbypass_all) / 60))
    cat(sprintf("Overall IQR: %.2f - %.2f minutes (%.2f - %.2f hours)\n",
                quantile(cpbypass_all, 0.25), quantile(cpbypass_all, 0.75),
                quantile(cpbypass_all, 0.25) / 60, quantile(cpbypass_all, 0.75) / 60))
    cat(sprintf("Overall IQR Range: %.2f minutes (%.2f hours)\n",
                IQR(cpbypass_all), IQR(cpbypass_all) / 60))
  }
}
cat("========================================\n")

