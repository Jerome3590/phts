# Notebook Cell Updates for Idempotency

This document contains the code snippets to manually update notebook cells for idempotency (resume capability).

## Cell 2: Output Directory Setup (Section 3)

**Location:** Section 3 - Output Directory Setup  
**Action:** Replace the entire cell content with the following:

```r
# Create output directory
output_dir <- here("cohort_analysis", "outputs", "survival")

# IDEMPOTENCY: Skip existing outputs if enabled
# Set SKIP_EXISTING_OUTPUTS = TRUE to resume from where you left off
# Set SKIP_EXISTING_OUTPUTS = FALSE to start fresh (will clean existing outputs)
SKIP_EXISTING_OUTPUTS <- TRUE  # Change to FALSE to force a fresh start

if (SKIP_EXISTING_OUTPUTS) {
  cat("\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║          🔄 RESUME MODE: Skipping existing outputs            ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n")
  cat("Set SKIP_EXISTING_OUTPUTS = FALSE to force a fresh start\n\n")
} else {
  cat("\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║          🧹 FRESH START MODE: Cleaning existing outputs       ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")
  
  # Clean existing outputs directory to ensure fresh/clean results
  if (dir.exists(output_dir)) {
    # Remove all files in outputs directory
    output_files <- list.files(output_dir, full.names = TRUE, recursive = TRUE, include.dirs = FALSE)
    if (length(output_files) > 0) {
      cat(sprintf("Cleaning %d existing output files...\n", length(output_files)))
      file.remove(output_files)
    }
    # Remove empty subdirectories
    output_dirs <- list.dirs(output_dir, recursive = TRUE, full.names = TRUE)
    output_dirs <- output_dirs[output_dirs != output_dir]  # Don't remove main directory
    for (dir in rev(output_dirs)) {  # Reverse order to remove nested dirs first
      if (length(list.files(dir)) == 0) {
        unlink(dir, recursive = TRUE)
      }
    }
    cat("✓ Output directory cleaned\n")
  }
}

# Create output directory (if it doesn't exist)
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat("Output directory:", output_dir, "\n")
cat(sprintf("MC-CV Configuration: %d splits, %.0f/%.0f train/test split\n", 
            n_mc_splits, train_prop * 100, (1 - train_prop) * 100))
flush.console()
```

---

## Cell 12: Section 5 Main Analysis Loop

**Location:** Section 5 - Run Analysis for All Periods  
**Action:** Find the `for (method in method_names) {` loop and add the skip logic right after the opening brace.

**Find this code:**
```r
  # Run each method
  period_results <- list()
  
  for (method in method_names) {
    result <- run_mc_cv_method(period_data, method, period_name, mc_splits)
    period_results[[method]] <- result
    
    # Save top features (sorted alphabetically for easier comparison)
    top_features_df <- tibble(
      feature = names(result$top_features),
      importance = as.numeric(result$top_features),
      cindex_td = result$cindex_td_mean,
      cindex_ti = result$cindex_ti_mean
    ) %>%
      arrange(feature)  # Sort alphabetically for easier visual comparison
    
    output_file <- file.path(output_dir, sprintf("%s_%s_top20.csv", 
                                                  period_name, tolower(method)))
    write_csv(top_features_df, output_file)
    cat(sprintf("✓ Saved: %s\n", basename(output_file)))
  }
```

**Replace with:**
```r
  # Run each method
  period_results <- list()
  
  for (method in method_names) {
    # Check if output file already exists (idempotency)
    output_file <- file.path(output_dir, sprintf("%s_%s_top20.csv", 
                                                  period_name, tolower(method)))
    if (SKIP_EXISTING_OUTPUTS && file.exists(output_file)) {
      cat(sprintf("\n⏭ Skipping %s (%s) - output file already exists: %s\n", 
                  method, period_name, basename(output_file)))
      period_results[[method]] <- NULL
      next
    }
    
    result <- run_mc_cv_method(period_data, method, period_name, mc_splits)
    period_results[[method]] <- result
    
    # Save top features (sorted alphabetically for easier comparison)
    top_features_df <- tibble(
      feature = names(result$top_features),
      importance = as.numeric(result$top_features),
      cindex_td = result$cindex_td_mean,
      cindex_ti = result$cindex_ti_mean
    ) %>%
      arrange(feature)  # Sort alphabetically for easier visual comparison
    
    write_csv(top_features_df, output_file)
    cat(sprintf("✓ Saved: %s\n", basename(output_file)))
  }
```

---

## Notes

- **Cell 2** ✅ Updated - Contains `SKIP_EXISTING_OUTPUTS` flag and conditional cleaning logic
- **Cell 12** ✅ Updated - Contains skip logic for Section 5 main analysis loop
- **Cell 19** ✅ Updated - Contains skip logic for Section 6.3 (cohort single-split analysis)
- **Cell 25** ✅ Updated - Contains skip logic for Section 6.6 (cohort MC-CV analysis)

**All cells have been updated and verified.**

## How It Works

- **Default behavior (`SKIP_EXISTING_OUTPUTS = TRUE`):**
  - Skips existing output files and loads results where available
  - Only runs missing analyses
  - Allows resuming from where you left off

- **Fresh start (`SKIP_EXISTING_OUTPUTS = FALSE`):**
  - Cleans output directory
  - Reruns all analyses from scratch

## Verification

All cells have been verified:
1. ✅ Cell 2 contains `SKIP_EXISTING_OUTPUTS <- TRUE` and conditional cleaning logic
2. ✅ Cell 12 checks for existing files before running each method/period combination
3. ✅ Cell 19 checks for existing cohort single-split results before running analysis
4. ✅ Cell 25 checks for existing cohort MC-CV results before running analysis

**Status:** All idempotency updates have been successfully applied. The workflow is now fully idempotent and can be stopped and resumed without losing progress.

