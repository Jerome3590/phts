# tx_mcsd Column Name Fix

## Problem

After fixing the pipeline exit errors and data flow issues, Step 4 was still reporting one missing Wisotzkey feature:

```
[WARNING] Missing Wisotzkey features: txmcsd
```

## Root Cause

**Column name mismatch between expected and actual names:**

- **Expected:** `txmcsd` (no underscore)
- **Actual:** `tx_mcsd` (with underscore)

The SAS source data has the column name `TX_MCSD` (with underscore), and after `janitor::clean_names()` it becomes `tx_mcsd` (lowercase with underscore). However, all the hardcoded Wisotzkey feature lists throughout the codebase were using `"txmcsd"` (no underscore).

## Solution

Updated all hardcoded Wisotzkey feature lists to use the correct column name: `"tx_mcsd"` (with underscore).

### Files Updated

1. ✅ `pipeline/01_prepare_data.R` - Updated wisotzkey_features list
2. ✅ `pipeline/04_fit_model.R` - Updated wisotzkey_features list  
3. ✅ `scripts/R/clean_phts.R` - Updated mutate() logic and missing_whitelist
4. ✅ `scripts/R/fit_models_parallel.R` - Updated wisotzkey_features list
5. ✅ `scripts/R/fit_models_fallback.R` - Updated fallback_vars list
6. ✅ `scripts/R/make_final_features.R` - Updated wisotzkey_variables list
7. ✅ `scripts/R/make_labels.R` - Updated add_row() variable name
8. ✅ `scripts/R/run_mc.R` - Updated continuous_vars list

### Key Changes

**BEFORE:**
```r
wisotzkey_features <- c(
  "prim_dx",       # Primary Etiology
  "txmcsd",        # MCSD at Transplant (NO underscore!)  ❌ WRONG
  "chd_sv",        # Single Ventricle CHD
  ...
)
```

**AFTER:**
```r
wisotzkey_features <- c(
  "prim_dx",       # Primary Etiology
  "tx_mcsd",       # MCSD at Transplant (with underscore!) ✅ CORRECT
  "chd_sv",        # Single Ventricle CHD
  ...
)
```

### Special Handling in clean_phts.R

Updated the mutate() logic to handle both naming conventions for backward compatibility:

```r
tx_mcsd = if ('txnomcsd' %in% names(.)) {
  # Convert txnomcsd (no mechanical support) to tx_mcsd
  if_else(txnomcsd == 'yes', 0, 1)
} else if ('tx_mcsd' %in% names(.)) { 
  # Use existing tx_mcsd column (most common)
  tx_mcsd
} else if ('txmcsd' %in% names(.)) {
  # Fallback: handle if column is named without underscore
  txmcsd
} else {
  NA_real_  # Column not found
}
```

Also updated the missing data whitelist to include both names:
```r
missing_whitelist <- c('tx_mcsd','txmcsd','chd_sv','lsfprat','lsfprab')
```

## Expected Result

After this fix:
- ✅ All 15 Wisotzkey features should be found
- ✅ No more "Missing Wisotzkey features: txmcsd" warning
- ✅ Step 4 data setup should complete successfully
- ✅ Model fitting should proceed with all intended features

## Verification

Check Step 4 output should now show:
```
[DEBUG] Wisotzkey features: 15 available, 0 missing
```

Instead of:
```
[DEBUG] Wisotzkey features: 14 available, 1 missing
[WARNING] Missing Wisotzkey features: txmcsd
```

---

**Date:** 2025-10-14  
**Issue:** Missing tx_mcsd Wisotzkey feature due to column name mismatch  
**Status:** FIXED ✅

