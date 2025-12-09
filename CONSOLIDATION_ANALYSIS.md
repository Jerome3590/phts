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

### Option 1: Merge into clinical_feature_importance_by_cohort (RECOMMENDED)

**Why this makes more sense:**
1. ✅ **Better structure** - Single, well-organized Jupyter notebook vs multiple Quarto documents
2. ✅ **More sophisticated methodology** - Already has MC-CV workflow (the critical missing piece)
3. ✅ **Survival focus** - Aligns with original study methodology (survival analysis)
4. ✅ **Modifiable features focus** - Clinical, actionable focus is the primary goal
5. ✅ **Easier to extend** - Notebook format is more flexible for adding workflows
6. ✅ **Existing infrastructure** - Helper functions, visualization scripts already in place

**Add to clinical_feature_importance_by_cohort:**
1. Classification models (from `cohort_analysis`):
   - LASSO (logistic)
   - CatBoost classification
   - CatBoost RF classification
   - Traditional RF classification
2. FFA workflow (from `cohort_analysis`)
3. 3 COAs (from `cohort_analysis`):
   - COA1: Observed-only labels
   - COA2: Observed-only (txpl_year < 2023)
   - COA3: IPCW-weighted labels
4. IPCW weighting support (from `cohort_analysis`)
5. Event classification workflow (1-year binary outcome)

**Keep from clinical_feature_importance_by_cohort:**
- MC-CV workflow for survival models (core methodology)
- Survival models (RSF, AORSF, CatBoost-Cox, XGBoost-Cox, XGBoost-Cox RF)
- Modifiable clinical features focus
- C-index aggregation with confidence intervals
- Existing visualization and helper functions

**Result:** `clinical_feature_importance_by_cohort` becomes comprehensive cohort analysis pipeline with:
- **Dynamic mode selection** - Run either survival OR classification analysis
- Survival models with MC-CV (existing - core)
- Classification models (add from `cohort_analysis`)
- Modifiable features focus (existing)
- XGBoost-Cox models (existing)

### Option 2: Merge into cohort_analysis (Not Recommended)

**Why this is less ideal:**
1. ❌ **Fragmented structure** - Multiple Quarto documents vs single notebook
2. ❌ **Less sophisticated** - Would need to add MC-CV workflow (major addition)
3. ❌ **Different focus** - Classification vs survival (survival is more aligned with study)
4. ❌ **More complex** - Multiple files to maintain and coordinate

### Option 3: Keep Separate (Not Recommended)

**Rationale:** Different focuses (survival MC-CV vs classification/FFA)

**Downside:** Duplication, maintenance burden, confusion, two places to look for cohort analysis

## Recommendation

**Consolidate INTO `clinical_feature_importance_by_cohort`** and add event classification functionality from `cohort_analysis`. This creates a unified, comprehensive cohort analysis pipeline that:

1. ✅ **Keeps the sophisticated MC-CV survival workflow** (core methodology)
2. ✅ **Adds event classification models** (from `cohort_analysis`)
3. ✅ **Makes notebook dynamic** - Can run either survival OR classification analysis
4. ✅ **Maintains modifiable features focus** (existing)
5. ✅ **Uses single notebook structure** (easier to maintain)

**Implementation Approach:**
- Add configuration flag: `ANALYSIS_MODE <- "survival"` or `"classification"`
- Conditional sections based on mode
- Survival mode: Uses existing MC-CV workflow with survival models
- Classification mode: Uses classification models with binary outcome at 1 year

## Next Steps

1. ✅ Review this analysis
2. ✅ Decide on consolidation approach: **Consolidate INTO `clinical_feature_importance_by_cohort`**
3. ✅ Scope confirmed:
   - ✅ Add event classification models
   - ✅ Make notebook dynamic (survival OR classification mode)
   - ❌ Skip 3 COAs (not needed)
   - ❌ Skip FFA (not complete)
4. Create migration plan:
   - Add `ANALYSIS_MODE` configuration flag
   - Add classification models section (conditional on mode)
   - Add classification metrics (AUC, Brier, Accuracy, Precision, Recall, F1)
   - Add data preparation for classification (1-year binary outcome)
   - Make existing survival sections conditional on `ANALYSIS_MODE == "survival"`
   - Update helper functions to support both modes
5. Move classification functionality FROM `cohort_analysis` TO `clinical_feature_importance_by_cohort`
6. Update documentation
7. Archive or remove `cohort_analysis` directory (or keep as reference)

