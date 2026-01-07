# Running All Models - Status

## Models Being Run

The calculator is now running **all 5 models** for **all 3 cohorts**:

### Models
1. **Simple Calculator** (Logistic Regression) - Baseline interpretable model
2. **CatBoost** - Gradient boosting with categorical feature support
3. **XGBoost** - Extreme gradient boosting
4. **XGBoost RF** - XGBoost in Random Forest mode
5. **LASSO** - L1-regularized logistic regression

### Cohorts
1. **CHD** - Congenital Heart Disease only
2. **Combined** - All primary diagnoses
3. **Myocardio** - Cardiomyopathy and Myocarditis only

## Configuration

- **MC-CV Splits**: 25 per cohort
- **Train/Test Split**: 80/20
- **Total Model Fits**: 25 splits × 3 cohorts × 5 models = **375 model fits**
- **Parallel Workers**: 18 (detected automatically)

## Expected Runtime

- **Estimated Time**: 1-2 hours on multi-core machine
- **Progress**: Can be monitored via `calculator_run_all_models.log`

## Improvements Made

1. **Better Error Handling**: Models now log errors instead of failing silently
2. **Progress Tracking**: First 3 splits show progress messages
3. **Suspicious AUC Detection**: Warns if AUC ≥ 0.99 (likely overfitting)

## Expected Results

Once complete, you should have:

### For Each Cohort:
- Simple Calculator results (baseline)
- CatBoost results
- XGBoost results
- XGBoost RF results
- LASSO results

### Output Files:
- `outputs/calculator_models_summary.csv` - Complete results table
- `outputs/best_models_by_cohort.csv` - Best model per cohort
- `outputs/importance_[COHORT]_[MODEL].csv` - Feature importance for each model

## Monitoring Progress

```bash
# Check log file
tail -f calculator_run_all_models.log

# Check for results
ls -lh outputs/calculator_models_summary.csv

# Quick status check
wc -l outputs/calculator_models_summary.csv
```

## Previous Results (Simple Calculator Only)

For reference, previous Simple Calculator results were:
- **CHD**: AUC = 0.625
- **Combined**: AUC = 0.738
- **Myocardio**: AUC = 0.657

We expect the tree-based models (CatBoost, XGBoost) to potentially perform better, especially for CHD with many categorical features.

---

*Started: [Current time]*
*Status: Running in background*
