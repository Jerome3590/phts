# Outputs and Plots Structure Standardization

## Standard Structure

All analysis workflows should follow this consistent structure:

```
<analysis_directory>/
├── outputs/              # Main outputs directory
│   ├── *.csv            # CSV result files
│   └── plots/           # Plots subdirectory
│       ├── *.png        # PNG plot files
│       ├── *.html       # HTML interactive plots
│       └── *.csv        # Plot data tables
```

## Standardized Patterns

### 1. Output Directory Creation

**Pattern:**
```r
output_dir <- here("<analysis_directory>", "outputs")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
```

**Examples:**
- Global Feature Importance: `here("feature_importance", "outputs")`
- Clinical Cohort: `here("clinical_feature_importance_by_cohort", "outputs")`

### 2. Plots Directory Creation

**Pattern:**
```r
plot_dir <- file.path(output_dir, "plots")

# Clean existing plots directory to ensure fresh/clean visualizations
if (dir.exists(plot_dir)) {
  plot_files <- list.files(plot_dir, full.names = TRUE, recursive = TRUE, include.dirs = FALSE)
  if (length(plot_files) > 0) {
    cat(sprintf("Cleaning %d existing plot files...\n", length(plot_files)))
    file.remove(plot_files)
  }
  cat("✓ Plots directory cleaned\n")
}
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)
```

**Note:** Both `create_visualizations.R` and `create_visualizations_cohort.R` now use this pattern.

### 3. Visualization Function Path Detection

**Standardized order (most specific to least specific):**

1. Check relative `outputs/` directory (for EC2 runs)
2. Check analysis-specific outputs directory
3. Check with `graft-loss/` prefix
4. Fallback to other analysis directories if needed

**Example for Clinical Cohort:**
```r
if (dir.exists("outputs")) {
  output_dir <- "outputs"
} else if (dir.exists(here("clinical_feature_importance_by_cohort", "outputs"))) {
  output_dir <- here("clinical_feature_importance_by_cohort", "outputs")
} else if (dir.exists(here("graft-loss", "clinical_feature_importance_by_cohort", "outputs"))) {
  output_dir <- here("graft-loss", "clinical_feature_importance_by_cohort", "outputs")
} else {
  stop("Cannot find outputs directory")
}
```

### 4. File Saving Patterns

**CSV Files:**
```r
write_csv(data, file.path(output_dir, "filename.csv"))
```

**Plot Files:**
```r
ggsave(file.path(plot_dir, "plot_name.png"), plot, width = 10, height = 8, dpi = 300)
```

## Implementation Status

### ✅ Completed

1. **`scripts/R/create_visualizations.R`**
   - ✅ Added plots directory cleaning
   - ✅ Consistent plot directory creation

2. **`scripts/R/create_visualizations_cohort.R`**
   - ✅ Updated to check clinical cohort outputs directory first
   - ✅ Consistent plots directory cleaning

### 📝 To Update

1. **`graft-loss/clinical_feature_importance_by_cohort/graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb`**
   - Update visualization function call to check for `clinical_feature_importance_by_cohort/outputs` first
   - Current: Checks `feature_importance/outputs` first (incorrect)
   - Should check: `clinical_feature_importance_by_cohort/outputs` first

2. **Other Analysis Workflows**
   - Review cohort_analysis, cohort_survival_analysis for consistent output directory patterns
   - Ensure all use `outputs/` and `outputs/plots/` structure

## Notes

- All outputs and plots directories are tracked in git (via `.gitignore` exceptions)
- Data artifacts (`.rds`, `.sas7bdat`, etc.) are excluded except in `outputs/` and `plots/`
- HTML files are excluded except in `outputs/` and `plots/`

