# Implementation Complete: Dynamic Notebook for Survival/Classification

## Summary

Successfully implemented dynamic analysis mode in `graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb` to support both:
- **Survival Analysis Mode** (existing functionality)
- **Event Classification Mode** (new functionality)

## Completed Tasks ✅

1. ✅ **ANALYSIS_MODE Configuration Flag**
   - Added `ANALYSIS_MODE <- "survival"` or `"classification"` flag
   - Conditional package loading for classification mode
   - Classification helper functions loaded when needed

2. ✅ **Updated prepare_modeling_data() Function**
   - Supports both survival and classification modes
   - Survival mode: Uses time/status columns (existing)
   - Classification mode: Creates outcome variable from ev_time/ev_type or uses existing outcome column

3. ✅ **Conditional Survival Sections**
   - Wrapped Section 10.1-10.4 in `if (ANALYSIS_MODE == "survival")` blocks
   - Survival analysis only runs when mode is set to "survival"

4. ✅ **Classification Models Section**
   - Added Section 11 for classification mode
   - Implemented 4 classification models:
     - LASSO (logistic regression)
     - CatBoost (classification)
     - CatBoost RF (classification)
     - Traditional RF (classification)

5. ✅ **Classification MC-CV Workflow**
   - MC-CV for classification models (same structure as survival)
   - Aggregates metrics: AUC, Brier Score, Accuracy, Precision, Recall, F1
   - 95% confidence intervals for all metrics
   - Results saved to `outputs/classification_mc_cv/`

6. ✅ **Documentation Updated**
   - README.md updated with dynamic mode documentation
   - Both modes documented with their respective models and metrics

## Implementation Details

### Configuration
- Set `ANALYSIS_MODE <- "survival"` or `"classification"` at top of notebook
- Classification packages load conditionally when mode is "classification"

### Data Preparation
- `prepare_modeling_data()` function handles both modes
- Classification mode creates `outcome` variable (1 if event by 1 year, 0 if no event with follow-up >= 1 year)
- Drops patients censored before 1 year

### Models

**Survival Mode:**
- RSF (ranger)
- AORSF
- CatBoost-Cox
- XGBoost-Cox (boosting)
- XGBoost-Cox RF mode
- Evaluation: C-index with 95% CI

**Classification Mode:**
- LASSO (logistic)
- CatBoost (classification)
- CatBoost RF (classification)
- Traditional RF (classification)
- Evaluation: AUC, Brier Score, Accuracy, Precision, Recall, F1 with 95% CI

### MC-CV Workflow
- Both modes use same MC-CV structure (configurable splits, default 100)
- Stratified sampling maintains event distribution
- Parallel processing with furrr/future
- Results aggregated with confidence intervals

## Files Modified

1. `graft-loss/clinical_feature_importance_by_cohort/graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb`
   - Added ANALYSIS_MODE flag
   - Updated package loading
   - Updated prepare_modeling_data() function
   - Wrapped survival sections conditionally
   - Added classification models section with MC-CV

2. `README.md`
   - Updated Clinical Cohort Feature Importance section
   - Documented both modes
   - Updated pipeline summary table

## Outputs

**Survival Mode:**
- `outputs/cohort_model_cindex_mc_cv_modifiable_clinical.csv`
- `outputs/best_clinical_features_by_cohort_mc_cv.csv`
- Visualizations in `outputs/plots/`

**Classification Mode:**
- `outputs/classification_mc_cv/cohort_classification_metrics_mc_cv.csv`

## Usage

1. **Survival Analysis:**
   ```r
   ANALYSIS_MODE <- "survival"
   # Run notebook - executes Section 10.1-10.4
   ```

2. **Event Classification:**
   ```r
   ANALYSIS_MODE <- "classification"
   # Run notebook - executes Section 11.1-11.5
   ```

## Next Steps (Optional)

- [ ] Add visualizations for classification mode
- [ ] Add feature importance extraction for classification models
- [ ] Add calibration plots for classification models
- [ ] Test both modes with full dataset

## Notes

- 3 COAs (different censoring strategies) were skipped per user request
- FFA workflow was skipped per user request (not complete)
- IPCW weighting not needed since COAs were skipped
- Classification mode uses same MC-CV structure as survival mode for consistency

