# Graft Loss Analysis Workflows

This directory contains all analysis workflows for pediatric heart transplant graft loss prediction, implementing Monte Carlo Cross-Validation (MC-CV) methodologies and multiple modeling approaches.

## Overview

The `graft-loss/` directory houses comprehensive analytical pipelines that replicate and extend the methodology from Wisotzkey et al. (2023). All workflows use robust MC-CV evaluation with proper train/test splitting and comprehensive feature selection.

## Analysis Workflows

### 1. Global Feature Importance (`feature_importance/`)

**Purpose**: Global feature selection across all patients using multiple methods

- **Notebook**: `graft_loss_feature_importance_20_MC_CV.ipynb`
- **Methods**: RSF, CatBoost, AORSF
- **Time Periods**: Original (2010-2019), Full (2010-2024), Full No COVID (2010-2024 excluding 2020-2023)
- **Output**: Top 20 features per method per period with C-index evaluation

**Quick Start**: See [`feature_importance/README.md`](feature_importance/README.md)

### 2. Clinical Cohort Analysis (`cohort_analysis/`)

**Purpose**: Cohort-specific analysis with modifiable clinical features (dynamic survival/classification modes)

- **Notebook**: `graft_loss_clinical_cohort_analysis.ipynb`
- **Cohorts**: CHD (Congenital Heart Disease) vs MyoCardio (Myocarditis/Cardiomyopathy)
- **Modes**: 
  - **Survival**: RSF, AORSF, CatBoost-Cox, XGBoost-Cox
  - **Classification**: LASSO, CatBoost, CatBoost RF, Traditional RF
- **Features**: Modifiable clinical features only (renal, liver, nutrition, respiratory, support devices, immunology)

**Quick Start**: See [`cohort_analysis/README.md`](cohort_analysis/README.md)

## Common Methodology

### Monte Carlo Cross-Validation (MC-CV)

All MC-CV workflows use:
- **Stratified sampling**: Maintains event distribution across splits
- **Train/Test Split**: 75/25 ratio (or 80/20 for cohort analysis)
- **Multiple Splits**: 100 splits for development, 1000 for publication
- **Parallel Processing**: furrr/future for fast execution
- **Confidence Intervals**: 95% CI for all metrics

### Evaluation Metrics

**Survival Analysis:**
- Time-dependent C-index (at 1-year horizon)
- Time-independent C-index (Harrell's C)
- Feature importance rankings

**Classification Analysis:**
- AUC (Area Under ROC Curve)
- Brier Score
- Accuracy, Precision, Recall, F1

### Data Source

- **File**: `data/phts_txpl_ml.sas7bdat`
- **Coverage**: 2010-2024 (TXPL_YEAR)
- **Censoring**: Proper handling with event times of 0 set to 1/365

### Variable Processing

Applied before all modeling:
- **CPBYPASS**: Removed (high missingness, not available in all periods)
- **DONISCH**: Dichotomized (>4 hours = 1, ≤4 hours = 0)

## Directory Structure

```
graft-loss/
├── README.md                                    # This file
├── feature_importance/                          # Global feature importance
│   ├── README.md                               # Workflow-specific README
│   ├── graft_loss_feature_importance_20_MC_CV.ipynb
│   └── outputs/                                # Analysis outputs
└── cohort_analysis/                            # Clinical cohort analysis
    ├── README.md                               # Workflow-specific README
    ├── graft_loss_clinical_cohort_analysis.ipynb
    └── outputs/                                # Analysis outputs
```

## Scripts

All executable scripts are in the root `scripts/` directory:
- **R Scripts**: `scripts/R/` (visualizations, helpers, analysis)
- **Python Scripts**: `scripts/py/` (FFA analysis, explainers)
- **Bash Scripts**: `scripts/bash/` (automation)

See [`../scripts/README.md`](../scripts/README.md) for details.

## Documentation

- **Detailed Documentation**: `docs/` folder (organized by workflow)
- **Shared Documentation**: `docs/shared/` (validation, leakage, variable mapping)
- **Standards**: `docs/scripts/` (logging, outputs, script organization)

See [`../docs/README.md`](../docs/README.md) for full documentation index.

## Quick Start

1. **Global Feature Importance**:
   ```bash
   cd feature_importance
   # Open graft_loss_feature_importance_20_MC_CV.ipynb
   # Set DEBUG_MODE <- FALSE
   # Run notebook
   ```

2. **Clinical Cohort Analysis**:
   ```bash
   cd cohort_analysis
   # Open graft_loss_clinical_cohort_analysis.ipynb
   # Set ANALYSIS_MODE <- "survival" or "classification"
   # Set DEBUG_MODE <- FALSE
   # Run notebook
   ```

## Outputs

All workflows save results to `outputs/` directories within each workflow folder:
- **CSV Files**: Summary tables, metrics, feature rankings
- **Plots**: Visualizations in `outputs/plots/` subdirectories
- **Logs**: Execution logs in `logs/` directories (if created)

## References

- Wisotzkey et al. (2023). Risk factors for 1-year allograft loss in pediatric heart transplant. *Pediatric Transplantation*.
- Original Repository: [bcjaeger/graft-loss](https://github.com/bcjaeger/graft-loss)

## Related Directories

- **`../scripts/`**: All executable scripts (R, Python, Bash)
- **`../docs/`**: Comprehensive documentation
- **`../concordance_index/`**: C-index implementation details
- **`../data/`**: PHTS registry data files

