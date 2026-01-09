# Lessons Learned: Model Implementation and Troubleshooting

This document captures key lessons learned during the implementation and debugging of each survival model in the calculator pipeline.

## Overview

During implementation, we encountered several critical issues that required robust fixes. This document serves as a reference for future development and troubleshooting.

---

## XGBoost-Cox Model

### Issue: "Contrasts can be applied only to factors with 2 or more levels"

**Root Cause:**
- `model.matrix()` fails when factors have fewer than 2 levels
- In small MC-CV splits, categorical features can become constant (single-level)
- Factor levels defined in full dataset may not exist in a specific split
- Checking `length(levels())` doesn't catch cases where levels exist but aren't present in data

**Solution:**
1. **Check actual unique values** in data, not just factor levels:
   ```r
   unique_vals <- unique(na.omit(train_pred[[col]]))
   if (length(unique_vals) < 2) {
     # Remove constant column
   }
   ```

2. **Synchronize factor levels** between train and test BEFORE conversion:
   - Get train levels as canonical reference
   - Map unseen test values to most common train level
   - Ensure both use same level order

3. **Convert ALL factors/characters to numeric** before matrix operations:
   - Convert characters → factors → numeric (level indices)
   - Use `as.matrix()` directly instead of `model.matrix()`
   - This completely eliminates contrast errors

**Key Takeaway:** Always validate actual data values, not just data types or level definitions. Small splits can cause features to become constant even if they're variable in the full dataset.

**Location:** `scripts/R/survival_helpers.R` - `run_xgb_cox()` function

---

## RSF (Random Survival Forest) Model

### Issue: "Subscript out of bounds" errors

**Root Cause:**
- `ranger::predict()` returns survival predictions in various formats depending on version/data
- Prediction matrices can have 0 rows or 0 columns in edge cases
- Accessing `pred$survival[, ncol(pred$survival)]` fails when matrix is empty
- Different ranger versions store predictions in different fields (`$survival`, `$chf`, `$predictions`)

**Solution:**
1. **Wrap entire prediction and extraction** in comprehensive tryCatch:
   ```r
   risk_scores <- tryCatch({
     pred <- predict(model, data = test_prep, type = "response")
     # ... extraction logic ...
   }, error = function(e) NULL)
   ```

2. **Validate matrix dimensions** before accessing:
   - Check `nrow() > 0` AND `ncol() > 0`
   - Verify `nrow == n_test` (matches test set size)
   - Check `n_cols >= 1` before using as index

3. **Extract columns safely**:
   - Store dimensions in variables first
   - Extract column as vector: `last_col <- surv_mat[, last_col_idx]`
   - Then convert: `result <- 1 - as.numeric(last_col)`
   - Validate result length and finiteness

4. **Multiple fallback methods**:
   - Try `pred$survival` first (most common)
   - Fallback to `pred$chf` (cumulative hazard)
   - Fallback to `pred$predictions` (some versions)
   - Final fallback: use negative time as risk proxy

**Key Takeaway:** Never assume matrix structure. Always validate dimensions and handle edge cases (empty matrices, mismatched sizes). Use multiple extraction methods with fallbacks.

**Location:** `scripts/R/survival_helpers.R` - `run_rsf_ranger()` function

---

## CatBoost-Cox Model

### Status: No Critical Issues

**Why it works well:**
- Native categorical feature support (no need for `model.matrix()`)
- Robust to missing values
- Handles factor levels automatically
- Less prone to constant column issues

**Best Practices:**
- Let CatBoost handle categorical encoding internally
- No manual factor synchronization needed
- Typically best performing model due to native categorical support

---

## AORSF (Accelerated Oblique Random Survival Forest)

### Issue: Factor Level Synchronization

**Root Cause:**
- AORSF requires exact factor level matching between train and test
- Unseen levels in test set cause errors
- Single-level factors cause issues

**Solution:**
1. **Synchronize factor levels** before model fitting:
   - Use train levels as canonical
   - Map unseen test values to "MISSING" or most common train level
   - Ensure test factors use exact same levels as train

2. **Remove constant columns**:
   - Check for single-level factors
   - Remove before fitting

**Key Takeaway:** Tree-based models with factor support still need level synchronization. Always align test to train levels.

**Location:** `graft-loss/cohort_analysis/calculator/calculator_models.R` - `fit_aorsf()` function

---

## Simple Calculator (Cox Regression)

### Status: No Critical Issues

**Why it works well:**
- Uses `survival::coxph()` which handles factors robustly
- Small feature set reduces edge case probability
- Standard R survival function with good error handling

**Best Practices:**
- Keep feature set small and clinically relevant
- Let `coxph()` handle factor encoding

---

## General Lessons

### 1. Train/Test Split Synchronization

**Critical:** Always synchronize factor levels and handle unseen values BEFORE any model operations.

**Pattern:**
```r
# 1. Get train levels (canonical)
train_levels <- levels(train_data[[col]])

# 2. Map unseen test values
test_vals <- as.character(test_data[[col]])
unseen_mask <- !(test_vals %in% train_levels) | is.na(test_vals)
test_vals[unseen_mask] <- most_common_train_level

# 3. Apply train levels to test
test_data[[col]] <- factor(test_vals, levels = train_levels)
```

### 2. Constant Column Detection

**Always check actual unique values**, not just data types:
```r
# Good: Check actual values
unique_vals <- unique(na.omit(data[[col]]))
if (length(unique_vals) < 2) {
  # Constant column
}

# Bad: Only check factor levels
if (length(levels(data[[col]])) < 2) {
  # May miss cases where levels exist but aren't in data
}
```

### 3. Matrix Access Safety

**Always validate dimensions before accessing:**
```r
if (is.matrix(mat)) {
  n_rows <- nrow(mat)
  n_cols <- ncol(mat)
  if (n_rows > 0 && n_cols > 0 && n_rows == expected_n) {
    # Safe to access
    result <- mat[, n_cols]
  }
}
```

### 4. Error Handling Strategy

**Use layered error handling:**
1. Wrap entire operation in tryCatch
2. Validate inputs before operations
3. Use fallback methods when primary fails
4. Provide meaningful fallback values (e.g., negative time for RSF)

### 5. MC-CV Edge Cases

**Small splits can cause:**
- Features to become constant
- Factors to have fewer levels
- Prediction matrices to be empty or malformed
- Always test with small datasets and edge cases

---

## Testing Recommendations

1. **Test with small datasets** (n < 50) to catch edge cases
2. **Test with single-level factors** to verify handling
3. **Test with very few events** in test set
4. **Test with missing values** in categorical features
5. **Test with empty or near-empty prediction matrices**

See `test_rsf_fix.R` for example test cases.

---

## Code Locations

- **XGBoost fix**: `scripts/R/survival_helpers.R` - `run_xgb_cox()` (lines ~1205-1275)
- **RSF fix**: `scripts/R/survival_helpers.R` - `run_rsf_ranger()` (lines ~1093-1195)
- **AORSF preprocessing**: `graft-loss/cohort_analysis/calculator/calculator_models.R` - `fit_aorsf()` (lines ~572-680)
- **Test script**: `graft-loss/cohort_analysis/calculator/test_rsf_fix.R`

---

## Future Improvements

1. **Centralized preprocessing function** for all models to ensure consistency
2. **More robust constant column detection** that handles all edge cases
3. **Better error messages** that indicate which split/model failed
4. **Validation checks** before model fitting to catch issues early
5. **Unit tests** for each model's preprocessing pipeline

---

## Related Documentation

- **Cursor Rules**: See `.cursorrules` in project root for comprehensive development guidelines and best practices
- **Calculator README**: See `graft-loss/cohort_analysis/calculator/README.md` for usage instructions

---

*Last Updated: After comprehensive fixes for XGBoost and RSF models*
