# Clinical Cohort Analysis

Dynamic analysis pipeline supporting both survival analysis and event classification with Monte Carlo Cross-Validation (MC-CV).

## Overview

This notebook (`graft_loss_clinical_cohort_analysis.ipynb`) implements cohort-specific analysis using **modifiable clinical features** for two etiologic cohorts:
- **CHD**: Congenital Heart Disease (`primary_etiology == "Congenital HD"`)
- **MyoCardio**: Myocarditis/Cardiomyopathy (`primary_etiology %in% c("Cardiomyopathy", "Myocarditis")`)

## Dynamic Mode Selection

Set `ANALYSIS_MODE` at the top of the notebook:

```r
ANALYSIS_MODE <- "survival"  # or "classification"
```

### Survival Analysis Mode (`ANALYSIS_MODE = "survival"`)

- **Models**: RSF (ranger), AORSF, CatBoost-Cox, XGBoost-Cox (boosting), XGBoost-Cox RF mode
- **Evaluation**: C-index with 95% CI across MC-CV splits
- **Features**: Modifiable clinical features only (renal, liver, nutrition, respiratory, support devices, immunology)

### Event Classification Mode (`ANALYSIS_MODE = "classification"`)

- **Models**: CatBoost (classification), CatBoost RF (classification), Traditional RF (classification), XGBoost (classification), XGBoost RF (classification)
- **Target**: Binary classification at 1 year (event by 1 year vs no event with follow-up >= 1 year)
- **Evaluation**: AUC, Brier Score, Accuracy, Precision, Recall, F1 with 95% CI across MC-CV splits

## Quick Start

1. Set `ANALYSIS_MODE` to desired mode ("survival" or "classification")
2. Set `DEBUG_MODE <- FALSE` for full analysis (or `TRUE` for quick test)
3. Run the notebook from top to bottom
4. Results saved to `outputs/` directory

## Outputs

- **Survival Mode**: 
  - `outputs/cohort_model_cindex_mc_cv_modifiable_clinical.csv`
  - `outputs/best_clinical_features_by_cohort_mc_cv.csv`
  - `outputs/plots/` - Visualizations

- **Classification Mode**: 
  - `outputs/classification_mc_cv/cohort_classification_metrics_mc_cv.csv`

## Documentation

For detailed documentation, see:
- **[Notebook Guide](docs/cohort_analysis/README_notebook_guide.md)** - Detailed notebook walkthrough
- **[Ready to Run](docs/cohort_analysis/README_ready_to_run.md)** - Execution instructions
- **[MC-CV Parallel EC2](docs/cohort_analysis/README_mc_cv_parallel_ec2.md)** - EC2 deployment guide
- **[Original vs Updated Study](docs/cohort_analysis/README_original_vs_updated_study.md)** - Methodology comparison
- **[Validation & Leakage](docs/shared/README_validation_concordance_variables_leakage.md)** - Validation procedures (shared)

## Scripts

Visualization scripts are in `scripts/R/`:
- `create_visualizations_cohort.R` - Creates cohort-specific visualizations

