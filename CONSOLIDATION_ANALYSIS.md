# Consolidation Analysis: clinical_feature_importance_by_cohort vs cohort_analysis

## Overview

Comparing functionality between `clinical_feature_importance_by_cohort` and `cohort_analysis` to identify what needs to be preserved during consolidation.

## Functionality Comparison

### clinical_feature_importance_by_cohort

**Focus:** Survival models with modifiable clinical features, MC-CV workflow

**Key Features:**
1. ✅ **MC-CV (Monte Carlo Cross-Validation)** - Extensive MC-CV workflow (50-100 splits)
2. ✅ **Survival Models:**
   - RSF (ranger)
   - AORSF
   - CatBoost-Cox
   - XGBoost-Cox (boosting)
   - XGBoost-Cox RF mode
3. ✅ **Modifiable Clinical Features Only** - Restricted to actionable features (renal, liver, nutrition, respiratory, support devices, immunology)
4. ✅ **C-index Evaluation** - Survival-specific concordance index
5. ✅ **Cohort-specific Models** - Separate models for CHD vs MyoCardio
6. ✅ **Feature Importance** - Top clinical features for best model per cohort
7. ✅ **Global 3-period MC-CV** - Also includes Original/Full/Full-No-COVID analysis

**Outputs:**
- `cohort_model_cindex_mc_cv_modifiable_clinical.csv`
- `best_clinical_features_by_cohort_mc_cv.csv`
- Visualizations (heatmaps, bar charts, Sankey diagrams)

### cohort_analysis

**Focus:** Event classification, comprehensive workflow comparison, FFA analysis

**Key Features:**
1. ✅ **Classification Models** - Binary classification at 1 year:
   - LASSO (logistic)
   - CatBoost
   - CatBoost RF
   - Traditional RF
2. ✅ **Survival Models** (in `cohort_survival_analysis.qmd`):
   - LASSO-Cox
   - AORSF
   - CatBoost-Cox
3. ✅ **3 COAs (Cohort Analytic Options)** - Different censoring strategies:
   - COA1: Observed-only labels
   - COA2: Observed-only (txpl_year < 2023)
   - COA3: IPCW-weighted labels
4. ✅ **FFA (Fast and Frugal Analysis)** - Formal Feature Attribution workflow
5. ✅ **Modifiable Clinical Features Analysis** (in `phts_feature_importance.qmd`)
6. ✅ **Feature Importance** - Multiple methods (LASSO, CatBoost, AORSF)
7. ✅ **Workflow Comparison** - Unified vs cohort-based strategies
8. ✅ **Event Classification** - 1-year binary outcome prediction

**Outputs:**
- `preprocessed_model_data_coa1.csv`, `coa2.csv`, `coa3.csv`
- `cohort_event_classification_summary.csv`
- `workflow_comparison_summary.csv`
- FFA outputs in `ffa_outputs/`
- Multiple HTML reports

## What clinical_feature_importance_by_cohort is MISSING from cohort_analysis

### Critical Missing Features:

1. **❌ MC-CV Workflow for Survival Models**
   - `cohort_analysis` does NOT have extensive MC-CV for survival models
   - `clinical_feature_importance_by_cohort` has 50-100 MC-CV splits per cohort
   - This is a **major methodological difference**

2. **❌ XGBoost-Cox Models**
   - `cohort_analysis` has XGBoost but may not have XGBoost-Cox survival variant
   - `clinical_feature_importance_by_cohort` has both XGBoost-Cox boosting and RF mode

3. **❌ Modifiable Clinical Features Focus**
   - While `cohort_analysis` has modifiable features analysis in `phts_feature_importance.qmd`, it's not the primary focus
   - `clinical_feature_importance_by_cohort` restricts ALL analysis to modifiable features only

4. **❌ C-index Aggregation Across MC-CV Splits**
   - `clinical_feature_importance_by_cohort` aggregates C-index with confidence intervals across many splits
   - `cohort_analysis` survival models may not have this aggregation

## What cohort_analysis has that clinical_feature_importance_by_cohort doesn't

1. **FFA Workflow** - Fast and Frugal Analysis for model interpretation
2. **3 COAs** - Different censoring strategies for handling censored data
3. **Classification Models** - Binary classification at 1 year (not survival)
4. **IPCW Weighting** - Inverse-probability-of-censoring weighting
5. **Workflow Comparison** - Unified vs cohort-based strategy comparison
6. **More Comprehensive Feature Set** - Uses all features, not just modifiable

## Consolidation Strategy

### Option 1: Merge into cohort_analysis (Recommended)

**Add to cohort_analysis:**
1. MC-CV workflow for survival models (from `clinical_feature_importance_by_cohort`)
2. XGBoost-Cox models (boosting and RF mode)
3. Modifiable clinical features-only workflow option
4. C-index aggregation with confidence intervals across MC-CV splits

**Keep from cohort_analysis:**
- All existing functionality (FFA, COAs, classification models, etc.)

**Result:** `cohort_analysis` becomes comprehensive workflow with both:
- Classification models (existing)
- Survival models with MC-CV (from `clinical_feature_importance_by_cohort`)
- FFA workflow (existing)
- 3 COAs (existing)
- Modifiable features option (enhanced)

### Option 2: Keep Separate (Not Recommended)

**Rationale:** Different focuses (survival MC-CV vs classification/FFA)

**Downside:** Duplication, maintenance burden, confusion

## Recommendation

**Consolidate into `cohort_analysis`** and add the missing MC-CV survival workflow. This creates a unified, comprehensive cohort analysis pipeline that includes:

1. ✅ Classification models (existing)
2. ✅ Survival models with MC-CV (add from `clinical_feature_importance_by_cohort`)
3. ✅ FFA workflow (existing)
4. ✅ 3 COAs (existing)
5. ✅ Modifiable features option (enhance existing)
6. ✅ XGBoost-Cox models (add from `clinical_feature_importance_by_cohort`)

## Next Steps

1. Review this analysis
2. Decide on consolidation approach
3. Create migration plan
4. Move MC-CV survival workflow to `cohort_analysis`
5. Update documentation
6. Archive or remove `clinical_feature_importance_by_cohort` directory

