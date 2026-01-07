# Calculator Models

This directory contains three calculator models for pediatric heart transplant graft loss prediction:

> **📋 For detailed variable documentation and final results, see [README_FINAL_MODELS.md](README_FINAL_MODELS.md)**

1. **CHD Model** - Congenital Heart Disease cohort only
2. **Combined Model** - All primary diagnoses
3. **Myocardio Model** - Cardiomyopathy and Myocarditis cohort only

## Overview

Each model compares five different **survival models**:
- **Simple Calculator** - Cox regression with selected clinical features (baseline)
- **CatBoost-Cox** - Gradient boosting with categorical feature support (iterations=1200)
- **XGBoost-Cox** - Extreme gradient boosting (nrounds=400)
- **AORSF** - Accelerated Oblique Random Survival Forest (n_tree=100)
- **RSF** - Random Survival Forest using ranger (num.trees=500)

## Methodology

- **Monte Carlo Cross-Validation**: 25 random 80/20 train/test splits
- **Evaluation Metric**: C-index (Concordance) for time-to-event survival analysis
- **Feature Importance**: Aggregated across all MC-CV splits
- **Outcome Definition**: Time-to-event (graft loss) with censoring
- **Model Type**: Survival models (Cox regression) for time-to-event analysis

## Features Used

### Complete Feature Table

| Category | Feature Name | Type | Description | Used By | Notes |
|----------|--------------|------|-------------|---------|-------|
| **Demographics** | | | | | |
| | `age_listing` | Raw | Age at listing (years) | All models | |
| | `age_txpl` | Raw | Age at transplant (years) | All models | |
| **Prior Surgeries** | | | | | |
| | `hxsurg` | Raw | History of surgery | All models | |
| **CHD Subtype** | | | | | |
| | `chd_hlh` | Raw | Congenital heart disease - Hypoplastic Left Heart | All models | |
| | `chd_*` | Raw | All other CHD subtype variables | All models | CHD model only; 40+ variables |
| **PRA Related** | | | | | |
| | `lsfcpra` | Raw | Flow cytometry PRA at listing (%) | All models | |
| | `lsfprab` | Raw | Flow cytometry PRA (B-cell) at listing (%) | All models | |
| | `lsfprat` | Raw | Flow cytometry PRA (T-cell) at listing (%) | All models | |
| | `txfcpra` | Raw | Flow cytometry PRA at transplant (%) | All models | |
| **Kidney Function** | | | | | |
| | `egfr_tx` | **[CALCULATED]** | Estimated GFR at transplant (mL/min/1.73m²) | All models | Schwartz: 0.413 × height_txpl / txcreat_r |
| | `egfr_listing` | **[CALCULATED]** | Estimated GFR at listing (mL/min/1.73m²) | All models | Schwartz: 0.413 × height_listing / lcreat_r |
| | `egfr_tx_cat` | **[DERIVED]** | eGFR category at transplant | All models | severe (<30), moderate (30-60), mild (60-90), normal (≥90) |
| | `egfr_listing_cat` | **[DERIVED]** | eGFR category at listing | All models | severe (<30), moderate (30-60), mild (60-90), normal (≥90) |
| | `egfr_change` | **[CALCULATED]** | Change in eGFR (transplant - listing) | All models | |
| | `hxdysdia_bin` | **[DERIVED]** | History of dialysis (0/1) | All models | From `hxdysdia` |
| | `txbun_r_high` | **[DERIVED]** | BUN >30 (0/1) | All models | From `txbun_r` |
| **Liver Function** | | | | | |
| | `txbili_t_r` | Raw | Total bilirubin at transplant (mg/dL) | All models | |
| | `txbili_t_r_high` | **[DERIVED]** | Total bilirubin >1.5 (0/1) | All models | |
| | `txalt` | Raw | ALT at transplant (U/L) | All models | |
| | `txalt_high` | **[DERIVED]** | ALT >90 (0/1) | All models | |
| | `txast` | Raw | AST at transplant (U/L) | All models | If available |
| **Respiratory** | | | | | |
| | `txvent` | Raw | Ventilation at transplant | All models | |
| | `hxtrach` | Raw | History of tracheostomy | All models | |
| | `ltxtrach` | Raw | Tracheostomy at listing | All models | |
| **Cardiac Support** | | | | | |
| | `txvad` | Raw | VAD at transplant | All models | |
| | `txecmo` | Raw | ECMO at transplant | All models | |
| | `slecmo` | Raw | ECMO at listing | All models | |
| | `ecmo_combined` | **[DERIVED]** | ECMO at transplant OR listing (0/1) | All models | |
| **Nutrition** | | | | | |
| | `txpalb_r` | Raw | Pre-albumin at transplant (mg/dL) | All models | |
| | `txsa_r` | Raw | Serum albumin at transplant (g/dL) | All models | |
| | `txsa_r_low` | **[DERIVED]** | Serum albumin <3 (0/1) | All models | |
| | `txtp_r` | Raw | Total protein at transplant (g/dL) | All models | |
| | `bmi_txpl` | **[CALCULATED]** | BMI at transplant | All models | (weight_txpl / height_txpl²) × 703 |
| | `height_txpl` | Raw | Height at transplant (cm) | All models | |
| | `weight_txpl` | Raw | Weight at transplant (kg) | All models | |
| | `height_listing` | Raw | Height at listing (cm) | All models | If available |
| | `weight_listing` | Raw | Weight at listing (kg) | All models | If available |
| | `height_zscore_txpl` | **[CALCULATED]** | Height-for-age z-score | All models | WHO growth curve |
| | `height_percentile_txpl` | **[CALCULATED]** | Height-for-age percentile | All models | WHO growth curve |
| | `weight_zscore_txpl` | **[CALCULATED]** | Weight-for-age z-score | All models | WHO growth curve |
| | `weight_percentile_txpl` | **[CALCULATED]** | Weight-for-age percentile | All models | WHO growth curve |
| **Additional Variables** | | | | | |
| | `hxfonlvr_bin` | **[DERIVED]** | History of Fontan liver disease (0/1) | All models | CHD model only |
| | `primary_etiology` | Raw | Primary diagnosis | All models | Combined model only |
| **Other Features** | | | | | |
| | All other modifiable clinical features | Raw | From PHTS data | CatBoost, XGBoost, AORSF, RSF | After leakage filtering |

### Feature Type Legend

- **Raw**: Directly from PHTS data
- **[CALCULATED]**: Computed from other variables (e.g., eGFR, BMI, WHO z-scores)
- **[DERIVED]**: Created from raw variables (dichotomous, categories)

### Model-Specific Features

**Simple Calculator (Cox Regression):**
- Uses subset of key clinical features (see table above)
- CHD model: Includes all `chd_*` variables and `hxfonlvr_bin`
- Combined model: Includes `primary_etiology`

**CatBoost, XGBoost, AORSF, RSF:**
- Use all available features after leakage filtering
- Includes all features from `calculate_derived_features()`
- Automatically handles categorical features

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
- `Model`: Simple_Calculator, CatBoost, XGBoost, AORSF, or RSF
- `C_Index_Mean`: Mean C-index across MC-CV splits
- `C_Index_SD`: Standard deviation of C-index
- `C_Index_CI_Lower`: 2.5th percentile (lower bound of 95% CI)
- `C_Index_CI_Upper`: 97.5th percentile (upper bound of 95% CI)
- `N_Splits`: Number of successful splits

### Feature Importance Format
- `feature`: Feature name
- `importance`: Aggregated importance value (mean across splits)
- `cohort`: Cohort name
- `model`: Model name

## Requirements

- R >= 4.0
- Required packages: dplyr, readr, survival, ranger, aorsf, catboost, xgboost, glmnet, tidyr, purrr, tibble, janitor, haven, riskRegression, prodlim, rsample, furrr, future, progressr

## Notes

- The Simple Calculator uses a subset of key clinical features selected based on clinical relevance
- All models use the same train/test splits for fair comparison
- Missing values are imputed using median (numeric) or mode (categorical)
- Constant columns are automatically removed
- Models are evaluated on unseen test data only

## Performance Expectations

Expected C-index ranges:
- Simple Calculator: 0.35-0.50
- CatBoost: 0.55-0.65
- XGBoost: 0.50-0.65
- AORSF: 0.35-0.50
- RSF: 0.40-0.55

These ranges may vary by cohort and data characteristics. CatBoost typically performs best due to its ability to handle categorical features natively.
