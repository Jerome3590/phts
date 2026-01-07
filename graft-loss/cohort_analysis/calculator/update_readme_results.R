#!/usr/bin/env Rscript

# Script to update README_FINAL_MODELS.md with actual results
# Run this after calculator_models.R completes

library(here)
library(readr)
library(dplyr)
library(stringr)

# Read results
results_file <- here("graft-loss", "cohort_analysis", "calculator", "outputs", "calculator_models_summary.csv")
readme_file <- here("graft-loss", "cohort_analysis", "calculator", "README_FINAL_MODELS.md")

if (!file.exists(results_file)) {
  stop("Results file not found. Run calculator_models.R first.")
}

# Read results
results <- read_csv(results_file, show_col_types = FALSE)

# Filter to Simple Calculator only
simple_calc_results <- results %>%
  filter(Model == "Simple_Calculator") %>%
  arrange(Cohort)

# Read README
readme_content <- readLines(readme_file)

# Find and replace the results table
table_start <- which(str_detect(readme_content, "### Performance Summary"))
table_end <- which(str_detect(readme_content, "### Baseline Results"))[1] - 1

if (length(table_start) > 0 && length(table_end) > 0) {
  # Create new results table
  new_table <- c(
    "### Performance Summary",
    "",
    "| Cohort | Model | AUC Mean | AUC SD | AUC 95% CI Lower | AUC 95% CI Upper | N Splits |",
    "|--------|-------|----------|--------|------------------|------------------|----------|"
  )
  
  for (i in 1:nrow(simple_calc_results)) {
    row <- simple_calc_results[i, ]
    new_table <- c(new_table, sprintf(
      "| %s | %s | %.4f | %.4f | %.4f | %.4f | %d |",
      row$Cohort, row$Model, row$AUC_Mean, row$AUC_SD,
      row$AUC_CI_Lower, row$AUC_CI_Upper, row$N_Splits
    ))
  }
  
  new_table <- c(new_table, "")
  
  # Replace the section
  readme_content <- c(
    readme_content[1:(table_start - 1)],
    new_table,
    readme_content[(table_end + 1):length(readme_content)]
  )
  
  # Update the "Last Updated" line
  update_line <- which(str_detect(readme_content, "\\*\\*Last Updated\\*\\*:"))
  if (length(update_line) > 0) {
    readme_content[update_line] <- sprintf(
      "- **Last Updated**: %s (Results from improved models with primary_etiology and CHD-specific features)",
      Sys.Date()
    )
  }
  
  # Write updated README
  writeLines(readme_content, readme_file)
  cat("✓ Updated README_FINAL_MODELS.md with results\n")
  cat(sprintf("  - %d cohorts processed\n", nrow(simple_calc_results)))
  cat(sprintf("  - Results saved to: %s\n", readme_file))
} else {
  warning("Could not find results table section in README. Manual update may be needed.")
}

# Also create a summary of feature importance
importance_files <- list.files(
  here("graft-loss", "cohort_analysis", "calculator", "outputs"),
  pattern = "importance_.*_Simple_Calculator\\.csv",
  full.names = TRUE
)

if (length(importance_files) > 0) {
  cat("\n=== Feature Importance Summary ===\n")
  for (file in importance_files) {
    cohort_name <- str_extract(basename(file), "(?<=importance_)[^_]+")
    imp <- read_csv(file, show_col_types = FALSE) %>%
      arrange(desc(importance)) %>%
      head(10)
    
    cat(sprintf("\nTop 10 features for %s:\n", cohort_name))
    print(imp %>% select(feature, importance))
  }
}

cat("\n✓ README update complete!\n")
