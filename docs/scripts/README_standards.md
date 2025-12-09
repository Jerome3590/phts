# Scripts Standards and Conventions

This document consolidates all standards and conventions for scripts, logging, outputs, and script organization.

## Table of Contents

1. [Logging Standards](#logging-standards)
2. [Outputs and Plots Structure](#outputs-and-plots-structure)
3. [Script Consolidation](#script-consolidation)

---

## Logging Standards

Consistent logging patterns across all analysis workflows and scripts.

### Log File Location

Logs should follow the same pattern as `outputs/` and `plots/` - they should be relative to the notebook's current working directory.

**Standard Structure:**
```
<analysis_directory>/
├── outputs/              # CSV result files
│   └── plots/           # PNG, HTML, CSV plot files
└── logs/                # Log files (if created programmatically)
    └── *.log
```

**Pattern:**
- Each notebook runs from its own directory (e.g., `feature_importance/`, `cohort_analysis/`)
- Logs should be created relative to that directory: `logs/analysis.log`
- When using `tee` from command line, logs should be saved to `logs/` directory:

```bash
# From feature_importance/ directory
mkdir -p logs
Rscript scripts/R/replicate_20_features_MC_CV.R 2>&1 | tee logs/replication_1000.log

# From cohort_analysis/ directory  
mkdir -p logs
# Run notebook with output redirected to logs/
```

### Logging Prefixes

Use consistent prefixes for different message types:

- `→` - Action in progress
- `✓` - Success/completion
- `⚠` - Warning
- `✗` - Error

**Examples:**
```r
cat("→ Starting MC-CV analysis...\n")
cat("✓ MC-CV completed successfully\n")
cat("⚠ Warning: Some splits failed\n")
cat("✗ Error: Cannot find data file\n")
```

### Section Headers

Use clear section headers for major workflow steps:

```r
cat("\n=== Section Name ===\n")
cat("→ Step description\n")
# ... code ...
cat("✓ Step completed\n")
```

### Summary Outputs

Provide clear summary outputs at the end of major sections:

```r
cat("\n=== Summary ===\n")
cat("Total splits:", n_splits, "\n")
cat("Successful splits:", n_success, "\n")
cat("Mean C-index:", round(mean_cindex, 3), "\n")
cat("95% CI: [", round(ci_lower, 3), ", ", round(ci_upper, 3), "]\n")
```

---

## Outputs and Plots Structure

### Standard Structure

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

### Standardized Patterns

#### 1. Output Directory Creation

**Pattern:**
```r
output_dir <- here("<analysis_directory>", "outputs")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
```

**Examples:**
- Global Feature Importance: `here("feature_importance", "outputs")`
- Clinical Cohort: `here("cohort_analysis", "outputs")`

#### 2. Plots Subdirectory

**Pattern:**
```r
plot_dir <- file.path(output_dir, "plots")
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
```

#### 3. File Naming Conventions

**CSV Files:**
- Use descriptive names with workflow context
- Include method/period/cohort identifiers
- Examples:
  - `cindex_table.csv` - C-index summary table
  - `cohort_model_cindex_mc_cv_modifiable_clinical.csv` - Cohort-specific C-index
  - `best_clinical_features_by_cohort_mc_cv.csv` - Top features by cohort

**Plot Files:**
- Use descriptive names matching CSV conventions
- Include file type in name when helpful
- Examples:
  - `feature_importance_heatmap.png`
  - `cindex_heatmap.png`
  - `cohort_clinical_feature_sankey.html`

#### 4. Relative Path Detection

Visualization scripts should detect `outputs/` relative to the notebook's current working directory:

```r
run_visualizations <- function(output_dir = NULL) {
  # Determine outputs directory if not provided
  # Each notebook runs from its own directory, so outputs/ should be relative to cwd
  if (is.null(output_dir)) {
    current_dir <- getwd()
    if (dir.exists("outputs")) {
      output_dir <- "outputs"
    } else {
      stop("Cannot find outputs directory. Expected 'outputs/' relative to current working directory: ", current_dir)
    }
  }
  plot_dir <- file.path(output_dir, "plots")
  # ... rest of function
}
```

---

## Script Consolidation

All scripts have been consolidated into `scripts/` directory to match EC2 file structure and eliminate duplicates.

### Directory Structure

```
scripts/
├── R/          # R scripts for data processing, visualization, and analysis
├── py/         # Python scripts for specialized analyses
└── bash/       # Bash scripts for automation and orchestration
```

### Consolidated R Scripts (`scripts/R/`)

All R scripts are now in `scripts/R/`:

- **`create_visualizations.R`** - Global feature importance visualizations
  - Used by: `feature_importance` workflow
  
- **`create_visualizations_cohort.R`** - Clinical cohort visualizations  
  - Used by: `cohort_analysis` workflow
  
- **`replicate_20_features_MC_CV.R`** - MC-CV replication script
  - Used by: `feature_importance` workflow
  
- **`check_variables.R`** - Variable validation
  - Used by: `feature_importance` workflow
  
- **`check_cpbypass_iqr.R`** - CPBYPASS statistics
  - Used by: `feature_importance` workflow
  
- **`classification_helpers.R`** - Classification helper functions
  - Used by: `cohort_analysis` workflow (classification mode)
  
- **`survival_helpers.R`** - Survival analysis helpers
  - Used by: Multiple workflows

### Consolidated Python Scripts (`scripts/py/`)

- **`ffa_analysis.py`** - Main FFA (Fast and Frugal Analysis) pipeline
- **`catboost_axp_explainer.py`** - CatBoost model explainer for FFA
- **`catboost_axp_explainer2.py`** - Alternative CatBoost explainer implementation

### Usage from Notebooks

Notebooks automatically detect the script location:

```r
# R notebooks will check scripts/R/ directory
if (file.exists(here("scripts", "R", "create_visualizations.R"))) {
  source(here("scripts", "R", "create_visualizations.R"))
} else {
  stop("Cannot find scripts/R/create_visualizations.R")
}
```

### EC2 Compatibility

This structure matches the EC2 file structure:
- Scripts are in `scripts/R/`, `scripts/py/`, `scripts/bash/`
- Notebooks remain in their respective directories:
  - `graft-loss/feature_importance/` - Global feature importance analysis
  - `graft-loss/cohort_analysis/` - Clinical cohort analysis

---

## References

- **Main Scripts README**: [../scripts/README.md](../../scripts/README.md)
- **Validation & Leakage**: [../shared/README_validation_concordance_variables_leakage.md](../shared/README_validation_concordance_variables_leakage.md)

