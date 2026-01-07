# Calculator Models - Current Status

## Status: Running

The calculator models are currently running with **all fixes applied**.

## Issues Fixed

### 1. CatBoost Error ✅
- **Problem**: `verbose = FALSE` (logical) caused parsing error
- **Fix**: Changed to `verbose = 0L` (integer)
- **Status**: Fixed

### 2. XGBoost/XGBoost RF Error ✅
- **Problem**: "contrasts can be applied only to factors with 2 or more levels"
- **Fix**: Added code to remove single-level factors before `model.matrix()`
- **Status**: Fixed in all XGBoost functions

### 3. LASSO Error ✅
- **Problem**: Same single-level factor issue
- **Fix**: Added code to remove single-level factors
- **Status**: Fixed

## Current Run

- **Started**: [Running now]
- **Log File**: `calculator_run_fixed.log`
- **Expected Completion**: 1-2 hours
- **Models Running**: All 5 models for all 3 cohorts

## Expected Results

Once complete, you should have:

### Models per Cohort:
- Simple Calculator (Logistic Regression)
- CatBoost
- XGBoost
- XGBoost RF
- LASSO

### Total Expected Results:
- 3 cohorts × 5 models = **15 model results**
- Each with 25 MC-CV splits

## Previous Results (Before Fixes)

Only Simple Calculator completed successfully:
- CHD: 0.625
- Combined: 0.738
- Myocardio: 0.657

XGBoost/XGBoost RF only completed 3 splits for Combined (with suspicious AUC=1.0).

## Monitoring

```bash
# Check progress
tail -f calculator_run_fixed.log

# Check results
cat ../outputs/calculator_models_summary.csv
```

---

*Last updated: [Current time]*
