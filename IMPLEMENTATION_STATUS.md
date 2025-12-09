# Implementation Status: Dynamic Notebook for Survival/Classification

## Completed ✅

1. **ANALYSIS_MODE Configuration Flag**
   - ✅ Added `ANALYSIS_MODE <- "survival"` or `"classification"` flag
   - ✅ Added conditional package loading for classification mode
   - ✅ Added classification helper functions loading

2. **Updated prepare_modeling_data() Function**
   - ✅ Added mode parameter support
   - ✅ Survival mode: Uses time/status columns (existing)
   - ✅ Classification mode: Creates outcome variable from ev_time/ev_type or uses existing outcome column

## In Progress 🔄

3. **Conditional Data Preparation**
   - 🔄 Need to add conditional sections for classification data prep
   - 🔄 Need to handle outcome variable creation for classification mode

## Pending 📝

4. **Classification Models Section**
   - Need to add Section 10.x for classification models:
     - LASSO (logistic)
     - CatBoost (classification)
     - CatBoost RF (classification)
     - Traditional RF (classification)

5. **Make Survival Sections Conditional**
   - Need to wrap existing Section 10.1-10.4 in `if (ANALYSIS_MODE == "survival")` blocks

6. **Classification MC-CV Workflow**
   - Need to add MC-CV for classification models
   - Aggregate AUC, Brier, Accuracy, Precision, Recall, F1 with confidence intervals

7. **Update Visualizations**
   - Update visualization scripts to handle both modes
   - Different outputs for survival (C-index) vs classification (AUC, etc.)

8. **Update Documentation**
   - Update README to explain both modes
   - Add examples for both modes

## Next Steps

1. Add conditional wrapper around Section 10.1-10.4 (survival sections)
2. Add new Section 11.x for classification models (or make Section 10 conditional)
3. Add classification MC-CV workflow
4. Update visualization calls to be mode-aware
5. Test both modes
6. Update documentation

## Files Modified

- `graft-loss/clinical_feature_importance_by_cohort/graft_loss_clinical_feature_importance_by_cohort_MC_CV.ipynb`
  - Added ANALYSIS_MODE flag
  - Updated package loading
  - Updated prepare_modeling_data() function

## Files to Reference

- `graft-loss/cohort_analysis/cohort_event_classification.qmd` - Classification model implementations
- `scripts/R/classification_helpers.R` - Classification helper functions

