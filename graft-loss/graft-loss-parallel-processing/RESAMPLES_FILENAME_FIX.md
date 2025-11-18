# Resamples Filename Mismatch Fix

## Problem

Step 4 (Data Setup) was creating MC-CV splits "on the fly" instead of using the pre-generated resamples from Step 2:

```
[DEBUG] testing_rows.rds not found, will create MC-CV splits on the fly
[DEBUG] About to call rsample::mc_cv...
[DEBUG] Successfully created mc_cv_splits
[DEBUG] Created 20 MC-CV splits on the fly
```

## Root Cause

**Filename mismatch between Step 2 (save) and Step 4 (load):**

- **Step 2 (02_resampling.R) saves:** `model_data/resamples.rds` ✓
- **Step 4 (fit_models_parallel.R) looks for:** `model_data/testing_rows.rds` ✗

From the logs:
```
[Progress] ✓ Resamples saved: model_data/resamples.rds (0.05 seconds)
[Progress] ✓ Verified: resamples.rds exists (0.07 MB)
```

But Step 4 was looking for a different file, so it couldn't find the pre-generated splits.

## Why This Matters

Creating splits "on the fly" in Step 4 instead of reusing from Step 2:
- ❌ Defeats the purpose of Step 2 (separate resampling step)
- ❌ Makes results non-reproducible (different splits each time)
- ❌ Wastes computation time regenerating the same splits
- ❌ Can cause inconsistencies if splits differ between models

## Solution

Updated `scripts/R/fit_models_parallel.R` to load the correct filename:

**BEFORE:**
```r
# Load testing_rows from step 02 (if available)
testing_rows_path <- here::here('model_data', 'testing_rows.rds')
testing_rows <- NULL
if (file.exists(testing_rows_path)) {
  testing_rows <- readRDS(testing_rows_path)
  cat(sprintf("[DEBUG] Loaded testing_rows: %d splits\n", length(testing_rows)))
} else {
  cat("[DEBUG] testing_rows.rds not found, will create MC-CV splits on the fly\n")
}
```

**AFTER:**
```r
# Load testing_rows from step 02 (if available)
# Step 2 saves as 'resamples.rds', not 'testing_rows.rds'
testing_rows_path <- here::here('model_data', 'resamples.rds')
testing_rows <- NULL
if (file.exists(testing_rows_path)) {
  testing_rows <- readRDS(testing_rows_path)
  cat(sprintf("[DEBUG] Loaded resamples.rds: %d splits\n", length(testing_rows)))
} else {
  cat("[DEBUG] resamples.rds not found, will create MC-CV splits on the fly\n")
}
```

## Expected Result

After this fix, Step 4 should show:
```
[DEBUG] Loaded resamples.rds: 25 splits
```

Instead of:
```
[DEBUG] testing_rows.rds not found, will create MC-CV splits on the fly
[DEBUG] About to call rsample::mc_cv...
[DEBUG] Created 20 MC-CV splits on the fly
```

## Benefits

✅ **Reproducibility:** All models use the same CV splits from Step 2  
✅ **Efficiency:** No redundant split generation in Step 4  
✅ **Consistency:** Pipeline steps work together as designed  
✅ **Correctness:** MC-CV configuration from Step 2 is respected

---

**Date:** 2025-10-14  
**Issue:** Step 4 creating MC-CV splits on the fly instead of loading from Step 2  
**Status:** FIXED ✅

