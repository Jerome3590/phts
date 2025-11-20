# helpers.R Files Comparison

## Summary

**No, the helpers.R files are NOT the same.** They serve different purposes and have different scopes.

## File Comparison

| File | Lines | Functions | Purpose |
|------|-------|-----------|---------|
| `cohort_analysis/helpers.R` | 334 | 10 | Classification metrics and data utilities |
| `cohort_survival_analysis/helpers.R` | 1,395 | 42 | Survival analysis, classification metrics, and data utilities |

## Shared Functions (10 functions)

Both files contain these 10 functions:
1. `align_mm`
2. `calculate_calibration_metrics`
3. `create_calibration_plot`
4. `create_classification_metrics`
5. `create_metrics_summary`
6. `create_unified_train_test_split`
7. `get_top_features_normalized`
8. `impute_like`
9. `mode_level`
10. `nzv_cols`

**Note**: These shared functions may have slight differences (need to verify), but they serve the same purpose.

## Unique to `cohort_analysis/helpers.R`

**None** - All functions in this file are also in `cohort_survival_analysis/helpers.R`

## Unique to `cohort_survival_analysis/helpers.R` (32 functions)

Survival-specific functions:
1. `assert_no_leakage_targets`
2. `brier_ipcw`
3. `calibration_table`
4. `clean_survival_data_for_catboost`
5. `compute_c_index`
6. `compute_censored_time_median`
7. `compute_concordance_pair`
8. `create_survival_metrics`
9. `export_pycox_dataset`
10. `fix_non_positive_times`
11. `get_Ghat`
12. `get_or_create_unified_split`
13. `get_survival_leakage_keywords`
14. `ipcw_prob_from_scores`
15. `load_phts_transplant_dataset`
16. `log_survival_cindex`
17. `remove_leakage_predictors`
18. `resolve_phts_data_dir`
19. `run_aorsf`
20. `run_lasso_cox`
21. ... (and more)

## Key Differences

### `cohort_analysis/helpers.R`
- **Focus**: Classification metrics (accuracy, precision, recall, F1, AUC, Brier score)
- **Size**: Smaller, focused file
- **Use case**: Binary classification problems

### `cohort_survival_analysis/helpers.R`
- **Focus**: Survival analysis (C-index, survival metrics, time-to-event data)
- **Size**: Much larger, comprehensive file
- **Use case**: Survival analysis problems
- **Includes**: All classification functions PLUS survival-specific functions

## Recommendation

### Option 1: Keep Both (Current Approach)
- **Pros**: Each file is tailored to its specific use case
- **Cons**: Code duplication of shared functions
- **Action**: Rename for clarity:
  - `cohort_analysis/helpers.R` → `cohort_analysis/classification_helpers.R`
  - `cohort_survival_analysis/helpers.R` → `cohort_survival_analysis/survival_helpers.R`

### Option 2: Consolidate Shared Functions
- **Pros**: Single source of truth for shared utilities
- **Cons**: Requires refactoring
- **Action**: 
  1. Extract shared functions to `graft-loss/R/utils/shared_helpers.R`
  2. Keep cohort-specific functions in their respective directories
  3. Update both files to source the shared utilities

### Option 3: Make `cohort_survival_analysis/helpers.R` the Master
- **Pros**: Single comprehensive file
- **Cons**: `cohort_analysis` would include survival functions it doesn't need
- **Action**: 
  1. Remove `cohort_analysis/helpers.R`
  2. Update `cohort_analysis` scripts to source `cohort_survival_analysis/helpers.R`

## Recommendation: Option 1 (Rename for Clarity)

Since both files serve distinct purposes and the duplication is minimal (only 10 shared utility functions), I recommend:

1. **Rename files** for clarity:
   - `cohort_analysis/helpers.R` → `cohort_analysis/classification_helpers.R`
   - `cohort_survival_analysis/helpers.R` → `cohort_survival_analysis/survival_helpers.R`

2. **Document the overlap** in comments at the top of each file

3. **Consider future consolidation** if the shared functions grow significantly

This maintains the current organization while improving clarity about each file's purpose.

