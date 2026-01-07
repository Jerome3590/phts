# Calculator Models Implementation Summary

## Overview

Three calculator models have been created in the `graft-loss/cohort_analysis/calculator/` folder:

1. **CHD Model** - Congenital Heart Disease cohort only
2. **Combined Model** - All primary diagnoses
3. **Myocardio Model** - Cardiomyopathy and Myocarditis cohort only

## Files Created

### Main Scripts
- **`calculator_models.R`** - Main implementation script with all model functions and MC-CV logic
- **`run_calculator.R`** - Simple runner script for executing individual or all models

### Documentation
- **`README.md`** - Comprehensive documentation for users
- **`IMPLEMENTATION_SUMMARY.md`** - This file

## Models Implemented

Each calculator compares five algorithms:

1. **Simple Calculator** - Logistic regression with selected clinical features
   - Uses key features: age, eGFR, bilirubin, albumin, ECMO, etc.
   - Simple, interpretable model for clinical use

2. **CatBoost** - Gradient boosting with categorical feature support
   - 500 iterations, depth 6, learning rate 0.1
   - Handles categorical features natively

3. **XGBoost** - Extreme gradient boosting
   - 500 rounds, depth 4, learning rate 0.05
   - Early stopping with 25 rounds patience

4. **XGBoost RF** - XGBoost in Random Forest mode
   - 500 parallel trees, 1 boosting round
   - RF-like behavior with XGBoost implementation

5. **LASSO** - L1-regularized logistic regression
   - 5-fold cross-validation for lambda selection
   - Automatic feature selection via regularization

## Methodology

### Monte Carlo Cross-Validation
- **25 splits** (as specified)
- **80/20 train/test** split ratio
- **Stratified** by outcome to maintain event distribution
- **Parallel processing** using `furrr` package

### Evaluation
- **Metric**: AUC (Area Under the ROC Curve)
- **Outcome**: Binary classification at 1 year
  - Event by 1 year (graft loss) = 1
  - No event with follow-up >= 1 year = 0
  - Censored before 1 year = excluded

### Feature Importance
- Aggregated across all 25 MC-CV splits
- Mean importance value for each feature
- Saved separately for each model and cohort

## Features Implemented

All requested variables have been implemented:

### Demographics
- ✅ `AGE_LISTING`, `AGE_TXPL`

### Prior Surgeries
- ✅ `HXSURG`

### CHD Subtype
- ✅ `CHD_HLH` and other `CHD_*` variables

### PRA Related
- ✅ `LSFCPRA`, `LSFPRAB`, `LSFPRAT`

### Kidney Function
- ✅ `eGFR_TXPL`, `eGFR_LISTING` (calculated using Schwartz formula: 0.413 * height / creatinine)
- ✅ `TXBUN_R` (dichotomized at >30)
- ✅ `HXDYSDIA` (dichotomous)
- ✅ eGFR categories: <30 (severe), 30-60 (moderate), 60-90 (mild), >90 (normal)
- ✅ Change in eGFR from listing to transplant

### Liver Function
- ✅ `TXBILI_T_R` (dichotomized at >1.5)
- ✅ `TXALT` (dichotomized at >90)
- ✅ `TXAST` (available if needed)

### Respiratory
- ✅ `TXVENT`
- ✅ `HXTRACH`, `LTXTRACH` (available if needed)

### Cardiac Support
- ✅ `TXVAD`
- ✅ `TXECMO`, `SLECMO` (combined dichotomous variable)

### Nutrition
- ✅ `TXPALB_R`, `TXSA_R` (dichotomized at <3), `TXTP_R`
- ✅ Height and Weight Percentiles (via WHO calculations if available)
- ✅ Donor/Candidate Size comparison (calculated if donor data available)

### Additional Variables
- ✅ History of Fontan Associated Liver Disease (dichotomous) - Note: Will be "no" for cardiomyopathy subgroup
- ✅ History of dialysis (dichotomous)
- ✅ `TXFCPRA`, `LSFCPRA`

## Output Files

Results are saved to `graft-loss/cohort_analysis/calculator/outputs/`:

1. **`calculator_models_summary.csv`** - Combined summary for all cohorts
   - Columns: Cohort, Model, AUC_Mean, AUC_SD, AUC_CI_Lower, AUC_CI_Upper, N_Splits

2. **`best_models_by_cohort.csv`** - Best performing model for each cohort

3. **`importance_[COHORT]_[MODEL].csv`** - Feature importance for each model and cohort
   - Columns: feature, importance, cohort, model

## Usage Examples

### Run All Models
```r
source("graft-loss/cohort_analysis/calculator/calculator_models.R")
main()
```

### Run Specific Cohort (R)
```r
source("graft-loss/cohort_analysis/calculator/run_calculator.R")
# Then modify to run specific cohort, or use command line:
```

### Run from Command Line
```bash
Rscript graft-loss/cohort_analysis/calculator/run_calculator.R CHD
Rscript graft-loss/cohort_analysis/calculator/run_calculator.R Combined
Rscript graft-loss/cohort_analysis/calculator/run_calculator.R Myocardio
Rscript graft-loss/cohort_analysis/calculator/run_calculator.R All
```

## Data Requirements

- PHTS data file: `phts_txpl_ml.sas7bdat`
- Location checked in order:
  1. `data/phts_txpl_ml.sas7bdat`
  2. `graft-loss-parallel-processing/data/phts_txpl_ml.sas7bdat`
  3. `graft-loss/data/phts_txpl_ml.sas7bdat`
- Data filtered to `TXPL_YEAR >= 2010`

## Technical Details

### Missing Value Handling
- Numeric: Median imputation
- Categorical: Mode imputation
- Constant columns: Automatically removed

### Data Preprocessing
- Time variables: Fixed non-positive times using median censored time
- Outcome construction: Based on `ev_time` and `ev_type`
- Feature engineering: All derived features calculated before modeling

### Parallel Processing
- Uses `furrr` for parallel MC-CV splits
- Number of workers: `max(1, detectCores() - 2)`
- Progress bars via `progressr` package

## Performance Considerations

- **Runtime**: Approximately 1-2 hours for all three cohorts on a multi-core machine
- **Memory**: Moderate (depends on data size and number of features)
- **Scalability**: Can be run on EC2 instances or high-performance workstations

## Validation

- All models evaluated on **unseen test data only**
- **No data leakage**: Train/test split maintained throughout
- **Reproducibility**: Fixed random seeds (1997) for splits
- **Robustness**: 25 MC-CV splits provide stable estimates

## Next Steps

1. Run the models on your data
2. Review the summary tables to identify best models
3. Examine feature importance for clinical insights
4. Consider model calibration if needed
5. Deploy best models for clinical use

## Notes

- The Simple Calculator is designed to be interpretable and easy to use in clinical settings
- All other models are more complex but may achieve higher performance
- Feature importance can guide clinical decision-making
- Results should be validated on external datasets if possible
