# Scripts Directory

This directory contains all executable scripts organized by language, matching the EC2 file structure.

## Directory Structure

```
scripts/
├── R/          # R scripts for data processing, visualization, and analysis
├── py/         # Python scripts for specialized analyses
└── bash/       # Bash scripts for automation and orchestration
```

## R Scripts (`scripts/R/`)

### Visualization Scripts
- **`create_visualizations.R`**: Creates feature importance heatmaps, C-index heatmaps, and bar charts for global feature importance analysis
- **`create_visualizations_cohort.R`**: Creates cohort-specific visualizations including Sankey diagrams for clinical feature importance

### Analysis Scripts
- **`replicate_20_features_MC_CV.R`**: Monte Carlo cross-validation script for feature importance analysis (clinical cohort version)

### Helper Scripts
- **`check_variables.R`**: Checks for DONISCH and CPBYPASS variables in the dataset
- **`check_cpbypass_iqr.R`**: Calculates CPBYPASS statistics (median, IQR) by period
- **`classification_helpers.R`**: Helper functions for cohort classification analysis
- **`survival_helpers.R`**: Helper functions for survival analysis

## Python Scripts (`scripts/py/`)

### FFA Analysis
- **`ffa_analysis.py`**: Main FFA (Fast and Frugal Analysis) pipeline
- **`catboost_axp_explainer.py`**: CatBoost model explainer for FFA
- **`catboost_axp_explainer2.py`**: Alternative CatBoost explainer implementation

**Note**: Python scripts may use relative imports. When running from different directories, ensure the Python path includes `scripts/py/` or run from the project root.

## Usage

### From Notebooks

Notebooks automatically detect the script location:

```r
# R notebooks will check both EC2 path and local path
if (file.exists(here("scripts", "R", "create_visualizations.R"))) {
  source(here("scripts", "R", "create_visualizations.R"))
}
```

### From Command Line

```bash
# R scripts
Rscript scripts/R/create_visualizations.R

# Python scripts (from project root)
python -m scripts.py.ffa_analysis
# Or add to PYTHONPATH
export PYTHONPATH="${PYTHONPATH}:$(pwd)/scripts"
python scripts/py/ffa_analysis.py
```

## EC2 Compatibility

This structure matches the EC2 file structure:
- Scripts are in `scripts/R/`, `scripts/py/`, `scripts/bash/`
- Notebooks remain in their respective directories:
  - `graft-loss/feature_importance/` - Global feature importance analysis
  - `graft-loss/clinical_feature_importance_by_cohort/` - Clinical cohort-specific feature importance
  - `graft-loss/cohort_analysis/` - Cohort analysis and classification

## Scripts by Analysis Directory

### Global Feature Importance (`graft-loss/feature_importance/`)
- Uses: `scripts/R/create_visualizations.R`
- Uses: `scripts/R/check_variables.R`
- Uses: `scripts/R/check_cpbypass_iqr.R`

### Clinical Cohort Analysis (`graft-loss/cohort_analysis/`)
- Uses: `scripts/R/create_visualizations_cohort.R`
- Uses: `scripts/R/classification_helpers.R`
- Uses: `scripts/py/ffa_analysis.py`
- Uses: `scripts/py/catboost_axp_explainer.py`
- Uses: `scripts/py/catboost_axp_explainer2.py`
- Notebook: `graft_loss_clinical_cohort_analysis.ipynb`

## Documentation

For detailed documentation on scripts and standards, see:
- **[Standards & Conventions](docs/scripts/README_standards.md)** - Consolidated standards document covering logging, outputs structure, and script organization

