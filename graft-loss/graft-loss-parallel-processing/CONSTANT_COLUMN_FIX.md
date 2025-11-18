# Constant Column Handling in MC-CV Folds

## Problem

During MC-CV (Monte Carlo Cross-Validation), some Wisotzkey features like `tx_mcsd` (MCSD at transplant) can become **constant within a specific training fold** due to:

1. **Low prevalence** - Most patients don't have MCSD (binary 0/1 variable heavily skewed to 0)
2. **Random CV splits** - A training fold might randomly contain only patients with tx_mcsd=0 (or only tx_mcsd=1)
3. **Model requirements** - ORSF/aorsf and other models reject truly constant predictors

### Error Message
```
[ERROR] Failed to fit final models: column tx_mcsd is constant.
Caused by error: ! column tx_mcsd is constant.
```

## Why This Happens

`tx_mcsd` is a clinically important predictor but has low variance:
- ✓ **Globally**: Has variance across the full dataset (some patients have MCSD, most don't)
- ✗ **In specific CV folds**: Can be constant (all 0s or all 1s) due to random sampling

This is a **legitimate statistical issue** with rare predictors in CV, not a data error.

## Solution

Added **graceful error handling** to model fitting functions to automatically handle constant columns in individual CV folds.

### Implementation in `fit_orsf.R`

```r
# Fit model using aorsf directly
# Handle constant column errors gracefully by removing problematic variables
model <- tryCatch({
  aorsf::orsf(
    data = trn[, c('time', 'status', vars)],
    formula = Surv(time, status) ~ .,
    n_tree = ntree,
    n_thread = aorsf_config$n_thread
  )
}, error = function(e) {
  # Check if error is about constant columns
  if (grepl("constant", e$message, ignore.case = TRUE)) {
    cat("[ORSF_WARNING] Constant column detected, attempting to fit without problematic variables\n")
    
    # Find truly constant columns in this fold
    constant_vars <- character(0)
    for (v in vars) {
      if (v %in% names(trn)) {
        if (is.numeric(trn[[v]])) {
          if (length(unique(trn[[v]][!is.na(trn[[v]])])) <= 1) {
            constant_vars <- c(constant_vars, v)
          }
        }
      }
    }
    
    if (length(constant_vars) > 0) {
      cat(sprintf("[ORSF_WARNING] Removing %d constant variables: %s\n", 
                  length(constant_vars), paste(constant_vars, collapse = ", ")))
      vars_filtered <- setdiff(vars, constant_vars)
      
      # Retry with filtered variables
      aorsf::orsf(
        data = trn[, c('time', 'status', vars_filtered)],
        formula = Surv(time, status) ~ .,
        n_tree = ntree,
        n_thread = aorsf_config$n_thread
      )
    } else {
      stop(e)  # Re-throw if we can't fix it
    }
  } else {
    stop(e)  # Re-throw non-constant-column errors
  }
})
```

## How It Works

1. **Try** to fit the model with all variables
2. **Catch** "constant column" errors
3. **Detect** which variables are truly constant in this fold
4. **Remove** only the constant variables
5. **Retry** fitting with the remaining variables
6. **Succeed** with a model using 14 features instead of 15 for this fold

## Benefits

✅ **Robustness**: Pipeline continues even when rare predictors are constant in specific folds  
✅ **Transparency**: Logs which variables were removed and why  
✅ **Validity**: Model is still fit with maximum available information  
✅ **Reproducibility**: Handles legitimate statistical issue, not hiding data problems

## Expected Behavior

### Before Fix
```
[ORSF_INIT] - tx_mcsd (zero variance)
[ERROR] Failed to fit final models: column tx_mcsd is constant.
Pipeline halts ✗
```

### After Fix
```
[ORSF_INIT] - tx_mcsd (zero variance)
[ORSF_WARNING] Constant column detected, attempting to fit without problematic variables
[ORSF_WARNING] Removing 1 constant variables: tx_mcsd
[Progress] ORSF model fitted successfully with 14 variables ✓
```

## When This Happens

This is **normal and expected** for:
- Rare binary indicators (tx_mcsd, txecmo, etc.)
- Small CV folds
- Highly skewed predictors

The model still fits using the other 14 Wisotzkey features for that specific fold. In other folds where tx_mcsd has variance, it will be included.

## Statistical Note

Across 25 MC-CV folds:
- Some folds: tx_mcsd constant → fit with 14 features
- Most folds: tx_mcsd varies → fit with 15 features
- **Average performance** across all folds is still valid for model comparison

This is the correct statistical approach for handling rare predictors in cross-validation.

---

**Date:** 2025-10-14  
**Issue:** ORSF failing on constant tx_mcsd in CV folds  
**Status:** FIXED ✅  
**File Modified:** `scripts/R/fit_orsf.R`

