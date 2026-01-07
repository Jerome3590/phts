# Calculator Models

This directory contains three calculator models for pediatric heart transplant graft loss prediction:

> **📋 For detailed variable documentation and final results, see [README_FINAL_MODELS.md](README_FINAL_MODELS.md)**

1. **CHD Model** - Congenital Heart Disease cohort only
2. **Combined Model** - All primary diagnoses
3. **Myocardio Model** - Cardiomyopathy and Myocarditis cohort only

## Overview

Each model compares five different algorithms:
- **Simple Calculator** - Logistic regression with selected clinical features
- **CatBoost** - Gradient boosting with categorical feature support
- **XGBoost** - Extreme gradient boosting
- **XGBoost RF** - XGBoost in Random Forest mode
- **LASSO** - L1-regularized logistic regression

## Methodology

- **Monte Carlo Cross-Validation**: 25 random 80/20 train/test splits
- **Evaluation Metric**: AUC (Area Under the ROC Curve) for 1-year graft loss prediction
- **Feature Importance**: Aggregated across all MC-CV splits
- **Outcome Definition**: Binary classification (event by 1 year vs no event with follow-up >= 1 year)

## Features Used

### Demographics
- `AGE_LISTING`, `AGE_TXPL`

### Prior Surgeries
- `HXSURG`

### CHD Subtype
- `CHD_HLH` and other `CHD_*` variables

### PRA Related
- `LSFCPRA`, `LSFPRAB`, `LSFPRAT`

### Kidney Function
- `eGFR_TXPL`, `eGFR_LISTING` (calculated using Schwartz formula)
- `TXBUN_R` (dichotomized at >30)
- `HXDYSDIA` (dichotomous)

### Liver Function
- `TXBILI_T_R` (dichotomized at >1.5)
- `TXALT` (dichotomized at >90)
- `TXAST` (if necessary)

### Respiratory
- `TXVENT`
- `HXTRACH`, `LTXTRACH` (if necessary)

### Cardiac Support
- `TXVAD`
- `TXECMO`, `SLECMO` (combined dichotomous variable)

### Nutrition
- `TXPALB_R`, `TXSA_R` (dichotomized at <3), `TXTP_R`
- Height and Weight Percentiles (calculated)
- Donor/Candidate Size comparison (calculated)

### Additional Variables
- History of Fontan Associated Liver Disease (dichotomous)
- History of dialysis (dichotomous)
- Change in eGFR from listing to transplant
- `TXFCPRA`, `LSFCPRA`

### eGFR Categories
- Severely depressed: <30
- Moderately depressed: 30-60
- Mildly depressed: 60-90
- Normal: >90

## Usage

### Run All Models

```r
source("graft-loss/cohort_analysis/calculator/calculator_models.R")
main()
```

### Run Individual Cohort

You can modify the `main()` function to run only specific cohorts by commenting out the others:

```r
# Run only CHD model
cohorts <- list(
  CHD = tx %>% filter(primary_etiology == "Congenital HD")
)
```

## Output Files

Results are saved to `graft-loss/cohort_analysis/calculator/outputs/`:

1. **`calculator_models_summary.csv`** - Summary table with AUC means, SDs, and 95% CIs for all models and cohorts
2. **`best_models_by_cohort.csv`** - Best performing model for each cohort
3. **`importance_[COHORT]_[MODEL].csv`** - Feature importance for each model and cohort

## Output Format

### Summary Table Columns
- `Cohort`: CHD, Combined, or Myocardio
- `Model`: Simple_Calculator, CatBoost, XGBoost, XGBoost_RF, or LASSO
- `AUC_Mean`: Mean AUC across 25 MC-CV splits
- `AUC_SD`: Standard deviation of AUC
- `AUC_CI_Lower`: 2.5th percentile (lower bound of 95% CI)
- `AUC_CI_Upper`: 97.5th percentile (upper bound of 95% CI)
- `N_Splits`: Number of successful splits

### Feature Importance Format
- `feature`: Feature name
- `importance`: Aggregated importance value (mean across splits)
- `cohort`: Cohort name
- `model`: Model name

## Requirements

- R >= 4.0
- Required packages: dplyr, readr, survival, ranger, aorsf, catboost, xgboost, glmnet, tidyr, purrr, tibble, janitor, haven, riskRegression, prodlim, rsample, furrr, future, progressr, pROC

## Notes

- The Simple Calculator uses a subset of key clinical features selected based on clinical relevance
- All models use the same train/test splits for fair comparison
- Missing values are imputed using median (numeric) or mode (categorical)
- Constant columns are automatically removed
- Models are evaluated on unseen test data only

## Performance Expectations

Expected AUC ranges:
- Simple Calculator: 0.65-0.75
- CatBoost: 0.70-0.80
- XGBoost: 0.70-0.80
- XGBoost RF: 0.70-0.80
- LASSO: 0.70-0.80

These ranges may vary by cohort and data characteristics.
