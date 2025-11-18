# Replicating 20-Feature Selection from Original Wisotzkey Study

## Overview

This script replicates the feature selection methodology from the original Wisotzkey et al. (2023) study, which selected **20 predictors** using permutation importance from Random Survival Forests (RSF). The script also compares this with CatBoost feature importance.

## What It Does

1. **Loads data** for pediatric heart transplant outcomes
2. **Defines three time periods**:
   - **Original study**: 2010-2019 (matches original publication)
   - **Full study**: 2010-2024 (all available data)
   - **Full study without COVID**: 2010-2024 excluding 2020-2023
3. **Runs RSF feature selection** with permutation importance (matching original study method)
4. **Runs CatBoost feature importance** for comparison
5. **Selects top 20 features** from each method
6. **Calculates C-index (concordance index)** for each model to assess discrimination performance
7. **Creates comparison tables** across time periods with performance metrics

## Key Differences from Original Study

- **Original study**: Used RSF permutation importance to select 20 features, then fit ORSF (Oblique Random Survival Forests)
- **This replication**: 
  - Uses RSF permutation importance (same as original)
  - Also includes CatBoost feature importance for comparison
  - Runs across multiple time periods to assess stability

## Output Files

All outputs are saved to `replicate_20_features_output/`:

### Individual Results
- `original_study_2010_2019_rsf_top20.csv` - Top 20 RSF features for original period (includes C-index)
- `original_study_2010_2019_catboost_top20.csv` - Top 20 CatBoost features for original period (includes C-index)
- `full_study_2010_2024_rsf_top20.csv` - Top 20 RSF features for full period (includes C-index)
- `full_study_2010_2024_catboost_top20.csv` - Top 20 CatBoost features for full period (includes C-index)
- `full_study_no_covid_2010_2024_excl_2020_2023_rsf_top20.csv` - Top 20 RSF features (no COVID, includes C-index)
- `full_study_no_covid_2010_2024_excl_2020_2023_catboost_top20.csv` - Top 20 CatBoost features (no COVID, includes C-index)

### Comparison Tables
- `rsf_comparison_all_periods.csv` - RSF features ranked across all periods (includes C-index)
- `rsf_comparison_wide.csv` - RSF features in wide format for easy comparison
- `catboost_comparison_all_periods.csv` - CatBoost features ranked across all periods (includes C-index)
- `catboost_comparison_wide.csv` - CatBoost features in wide format
- `rsf_feature_overlap.csv` - Features common to all periods (RSF)
- `catboost_feature_overlap.csv` - Features common to all periods (CatBoost)
- `summary_statistics.csv` - Sample sizes, event rates, and **C-index values** per period

## Usage

### Prerequisites

```r
# Required packages
install.packages(c("dplyr", "readr", "survival", "ranger", "tidyr", "purrr", "here"))
install.packages("catboost")  # Optional but recommended
```

### Running the Script

```r
# From project root directory
source("replicate_20_features.R")
```

### Expected Runtime

- RSF feature selection: ~5-10 minutes per time period (depends on data size)
- CatBoost feature importance: ~10-20 minutes per time period
- Total: ~45-90 minutes for all three periods

## Methodology Details

### RSF Feature Selection (Matching Original Study)

- **Method**: Random Survival Forests with permutation importance
- **Parameters**:
  - `num.trees = 500` (matching original study)
  - `importance = 'permutation'` (matching original study)
  - `min.node.size = 20`
  - `splitrule = 'extratrees'`
  - `num.random.splits = 10`
- **Selection**: Top 20 features by permutation importance

### CatBoost Feature Importance

- **Method**: CatBoost regression with signed-time labels
- **Parameters**:
  - `loss_function = 'RMSE'`
  - `depth = 6`
  - `learning_rate = 0.05`
  - `iterations = 2000`
  - `l2_leaf_reg = 3.0`
- **Labels**: Signed-time (+time for events, -time for censored)
- **Selection**: Top 20 features by feature importance
- **C-index**: Calculated using Harrell's concordance index on model predictions

## Model Performance Metrics

### C-index (Concordance Index)

The script calculates **Harrell's C-index** for each model:

- **RSF C-index**: Measures discrimination of RSF model predictions
- **CatBoost C-index**: Measures discrimination of CatBoost model predictions
- **Interpretation**:
  - C-index = 0.5: No discrimination (random)
  - C-index = 1.0: Perfect discrimination
  - C-index > 0.7: Good discrimination
  - C-index > 0.8: Excellent discrimination

The C-index values are:
- Included in each feature importance CSV file
- Reported in the summary statistics table
- Printed during script execution for each model

### Comparing Performance

- **Higher C-index** = better model discrimination
- Compare RSF vs CatBoost C-index to see which method performs better
- Compare C-index across time periods to assess model stability

## Interpreting Results

### Feature Stability

- **High overlap** across time periods suggests robust features
- **Low overlap** suggests period-specific effects or instability

### Comparing RSF vs CatBoost

- **RSF**: Permutation-based importance (model-agnostic)
- **CatBoost**: Gain-based importance (model-specific)
- Differences highlight which features are important for different model types
- **C-index comparison**: Compare discrimination performance between methods

### Model Performance

- **C-index values** show how well each model discriminates between high-risk and low-risk patients
- **Compare across periods**: Stable C-index suggests robust model performance
- **Compare methods**: Higher C-index indicates better discrimination for that method
- **Context**: Original study reported C-index ~0.74 for random forests and ~0.71 for Cox PH

### Original Study Context

The original study found that the top 3 variables by permutation importance were:
1. Cardiopulmonary bypass time
2. Primary etiology (cardiomyopathy, congenital heart disease, or other)
3. ECMO at transplant

Compare your results to see if these appear in the top 20 across different time periods.

## Troubleshooting

### Data Loading Issues

If the script can't find the data:
1. Check that you're running from the project root
2. Verify `data/transplant.sas7bdat` exists
3. Or check for `graft-loss-parallel-processing/model_data/phts_simple.rds`

### CatBoost Not Available

If CatBoost fails:
- The script will continue with RSF only
- Install CatBoost: `install.packages("catboost")`
- Or use Python CatBoost if R package unavailable

### Memory Issues

For large datasets:
- Reduce `n_trees_rsf` in the script (e.g., from 500 to 250)
- Process one time period at a time by modifying the script

## Next Steps

After running the script:

1. **Compare with original study**: Check if the top 3 features match
2. **Assess stability**: See which features appear consistently across periods
3. **Model fitting**: Use the selected features to fit ORSF models (as in original study)
4. **Validation**: Evaluate model performance with the selected features

## References

Wisotzkey et al. (2023). Risk factors for 1-year allograft loss in pediatric heart transplant. *Pediatric Transplantation*.

