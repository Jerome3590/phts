# Clinical Cohort Analysis

**Key Feature:** Cohort-specific analysis with modifiable clinical features for CHD vs MyoCardio cohorts.

Dynamic analysis pipeline supporting both survival analysis and event classification with Monte Carlo Cross-Validation (MC-CV).

## Overview

This analysis implements cohort-specific models using **modifiable clinical features** for two etiologic cohorts:
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

## Notebooks

- **`graft_loss_clinical_cohort_survival.ipynb`**: Survival analysis mode (default)
- **`graft_loss_clinical_cohort_event_classification.ipynb`**: Classification mode
- **`graft_loss_clinical_cohort_analysis.ipynb`**: Unified notebook supporting both modes

## Outputs

All outputs are saved to `graft-loss/cohort_analysis/outputs/` and synced to `s3://uva-private-data-lake/graft-loss/cohort_analysis/`.

### Survival Mode Outputs

- `outputs/survival/cohort_model_cindex_mc_cv_modifiable_clinical.csv` - Model performance metrics
- `outputs/survival/best_clinical_features_by_cohort_mc_cv.csv` - Feature importance by cohort
- `outputs/survival/summary/plots/` - Visualizations:
  - `cindex_heatmap.png` - Model performance comparison
  - `feature_importance_heatmap.png` - Feature importance heatmap
  - `scaled_feature_importance_bar_chart.png` - Scaled importance by cohort
  - `cohort_clinical_feature_sankey.html` - Sankey diagram of feature importance
  - `cohort_scaled_feature_importance_sankey.html` - Scaled Sankey diagram
- `outputs/survival/CHD/` and `outputs/survival/MyoCardio/` - Cohort-specific results

### Classification Mode Outputs

- `outputs/classification/cohort_model_metrics_mc_cv_modifiable_clinical.csv` - Classification metrics
- `outputs/classification/best_clinical_features_by_cohort_mc_cv.csv` - Feature importance
- `outputs/classification/summary/plots/` - Visualizations

## Feature Documentation

📋 **[Complete Feature Documentation](model_features/README.md)**

The detailed feature documentation includes:
- **Variables Kept**: 41 modifiable clinical features organized by category (Kidney Function, Liver Function, Nutrition, Respiratory, Cardiac Support, Immunology)
- **Variables Dropped**: Complete list of excluded variables with reasons
- **Top Features from Feature Importance Analysis**: Results from RSF, CatBoost, and AORSF models
- **Important Features Excluded**: Features identified as important but excluded due to non-modifiability
- **IQR for Numerical Variables**: Interquartile ranges for all continuous variables
- **Binary Features**: Distribution of binary (0/1) features
- **Mapping to Data Dictionary**: Links to PHTS variable definitions
- **Calculated Variables**: Documentation for eGFR, BMI, and WHO growth curve calculations

### Quick Feature Summary

- **Total Variables in PHTS Dataset**: 476
- **Modifiable Clinical Features Kept**: 41
- **Variables Excluded**: 43 exact matches + variables with prefixes (dtx_, cc_, dcon, dpri, dsec, dmaj, sd)

**Feature Categories:**
- Kidney Function (5 features)
- Liver Function (9 features)
- Nutrition (12 features)
- Respiratory (4 features)
- Cardiac Support (7 features)
- Immunology (4 features)

## Key Features

### Modifiable Clinical Features Only

The analysis focuses exclusively on **modifiable clinical features** that can be influenced through clinical intervention:

- **Kidney Function**: Creatinine monitoring, eGFR-based intervention, dialysis management
- **Liver Function**: AST/ALT monitoring, bilirubin assessment, Fontan liver disease management
- **Nutrition**: Albumin, pre-albumin, total protein, BMI, growth parameters
- **Respiratory**: Ventilation support, tracheostomy care
- **Cardiac Support**: VAD, ECMO, MCSD consideration, CPR risk mitigation
- **Immunology**: HLA desensitization, crossmatch-based donor selection, PRA monitoring

## Monte Carlo Cross-Validation

- **Splits**: 50 (or 5 in DEBUG_MODE)
- **Train/Test Split**: 80/20
- **Evaluation**: Performance metrics with 95% confidence intervals across splits

## Model Performance

### CHD Cohort
- **Sample Size**: ~2,845 patients
- **Event Rate**: ~20.11%
- **Best Model**: Varies by analysis mode (see outputs for details)

### MyoCardio Cohort
- **Sample Size**: ~2,914 patients
- **Event Rate**: ~12.01%
- **Best Model**: Varies by analysis mode (see outputs for details)

## Related Documentation

- **[Risk Dashboard README](README_risk_dashboard.md)** - Interactive risk prediction dashboard
- **[Final Model README](final_model/README_final_model.md)** - Production model documentation
- **[Integration Instructions](scripts/INTEGRATION_INSTRUCTIONS.md)** - How to integrate eGFR and WHO calculations

## Data Requirements

- **Input Data**: `graft-loss/data/phts_txpl_ml.sas7bdat`
- **Time Period**: 2010-2024 (configurable)
- **Cohorts**: CHD and MyoCardio (filtered by `primary_etiology`)

## Dependencies

- R packages: `survival`, `catboost`, `ranger`, `xgboost`, `aorsf`, `dplyr`, `tidyr`, `ggplot2`, `plotly`
- Optional: `zscorer` package for WHO growth curve calculations

## Scripts

- **`scripts/calculate_derived_features.R`**: Calculates eGFR, BMI, and WHO z-scores
- **`scripts/calculate_who_zscore.R`**: Helper functions for WHO growth curve calculations
- **`scripts/generate_feature_documentation.R`**: Generates feature documentation with IQR values

## Citation

If using this analysis, please cite the original PHTS registry and reference the feature documentation for complete variable definitions.

