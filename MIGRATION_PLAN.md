# Migration Plan: Consolidate cohort_analysis into clinical_feature_importance_by_cohort

## Goal

Make `clinical_feature_importance_by_cohort` notebook dynamic to support both:
- **Survival Analysis Mode** (existing)
- **Event Classification Mode** (add from `cohort_analysis`)

## What to Add

### 1. Configuration Flag

Add at top of notebook (near `DEBUG_MODE`):

```r
# Analysis mode: "survival" or "classification"
ANALYSIS_MODE <- "survival"  # or "classification"
```

### 2. Data Preparation (Conditional)

**Survival Mode (existing):**
- Uses `time` and `status` variables
- No changes needed

**Classification Mode (add):**
- Create `outcome` variable: 1 if event by 1 year, 0 if no event and follow-up >= 1 year
- Drop patients censored before 1 year (outcome = NA)
- Use `outcome` as binary target instead of `time`/`status`

### 3. Models (Conditional Sections)

**Survival Mode (existing):**
- RSF (ranger)
- AORSF
- CatBoost-Cox
- XGBoost-Cox (boosting)
- XGBoost-Cox RF mode
- Evaluation: C-index

**Classification Mode (add):**
- LASSO (logistic regression)
- CatBoost (classification)
- CatBoost RF (classification)
- Traditional RF (classification)
- Evaluation: AUC, Brier Score, Accuracy, Precision, Recall, F1

### 4. Helper Functions

Update helper functions to support both modes:
- `prepare_modeling_data()` - Add classification mode logic
- Model wrappers - Add classification variants
- Evaluation functions - Add classification metrics

### 5. MC-CV Workflow

**Survival Mode:**
- Keep existing MC-CV workflow (50-100 splits)
- Aggregate C-index with confidence intervals

**Classification Mode:**
- Add MC-CV for classification models
- Aggregate classification metrics (AUC, etc.) with confidence intervals

## Files to Reference from cohort_analysis

1. **`cohort_event_classification.qmd`**:
   - Classification model implementations
   - Classification metrics calculation
   - Data preparation for classification

2. **`event_classification.qmd`**:
   - Unified classification approach
   - Model comparison logic

3. **`scripts/R/classification_helpers.R`**:
   - Classification helper functions
   - Metrics calculation functions

## Implementation Steps

1. **Add configuration section** with `ANALYSIS_MODE` flag
2. **Add conditional data preparation** based on mode
3. **Add classification models section** (conditional on `ANALYSIS_MODE == "classification"`)
4. **Update existing survival sections** to be conditional on `ANALYSIS_MODE == "survival"`
5. **Add classification metrics** calculation and aggregation
6. **Update helper functions** to support both modes
7. **Update visualizations** to handle both modes
8. **Update documentation** to explain both modes

## What NOT to Add

- ❌ 3 COAs (different censoring strategies) - user confirmed not needed
- ❌ FFA workflow - user confirmed not complete
- ❌ IPCW weighting - not needed if skipping COAs

## Testing

After migration:
1. Test survival mode (should work as before)
2. Test classification mode (new functionality)
3. Verify outputs are correct for both modes
4. Update README documentation

