# Replicating 20-Feature Selection from Original Wisotzkey Study

## Overview

This script replicates the feature selection methodology from the original Wisotzkey et al. (2023) study, which selected **20 predictors** using permutation importance from Random Survival Forests (RSF). The script also compares this with CatBoost and AORSF (Accelerated Oblique Random Survival Forest) feature importance.

## What It Does

1. **Loads data** for pediatric heart transplant outcomes
2. **Defines three time periods**:
   - **Original study**: 2010-2019 (matches original publication)
   - **Full study**: 2010-2024 (all available data)
   - **Full study without COVID**: 2010-2024 excluding 2020-2023
3. **Runs RSF feature selection** with permutation importance (matching original study method)
4. **Runs CatBoost feature importance** for comparison
5. **Runs AORSF feature importance** for comparison (matching original study's final model)
6. **Selects top 20 features** from each method
7. **Calculates both time-dependent and time-independent C-index (concordance index)** for each model to assess discrimination performance
8. **Creates comparison tables** across time periods with performance metrics

## Key Differences from Original Study

- **Original study**: Used RSF permutation importance to select 20 features, then fit ORSF (Oblique Random Survival Forests)
- **This replication**: 
  - Uses RSF permutation importance (same as original)
  - Also includes CatBoost feature importance for comparison
  - Includes AORSF feature importance (matching the final model used in original study)
  - Runs across multiple time periods to assess stability
  - Provides both time-dependent and time-independent C-indexes for better comparison

## Output Files

All outputs are saved to `replicate_20_features_output/`:

### Individual Results
- `original_study_2010_2019_rsf_top20.csv` - Top 20 RSF features for original period (includes both C-index types)
- `original_study_2010_2019_catboost_top20.csv` - Top 20 CatBoost features for original period (includes both C-index types)
- `original_study_2010_2019_aorsf_top20.csv` - Top 20 AORSF features for original period (includes both C-index types)
- `full_study_2010_2024_rsf_top20.csv` - Top 20 RSF features for full period (includes both C-index types)
- `full_study_2010_2024_catboost_top20.csv` - Top 20 CatBoost features for full period (includes both C-index types)
- `full_study_2010_2024_aorsf_top20.csv` - Top 20 AORSF features for full period (includes both C-index types)
- `full_study_no_covid_2010_2024_excl_2020_2023_rsf_top20.csv` - Top 20 RSF features (no COVID, includes both C-index types)
- `full_study_no_covid_2010_2024_excl_2020_2023_catboost_top20.csv` - Top 20 CatBoost features (no COVID, includes both C-index types)
- `full_study_no_covid_2010_2024_excl_2020_2023_aorsf_top20.csv` - Top 20 AORSF features (no COVID, includes both C-index types)

### Comparison Tables
- `rsf_comparison_all_periods.csv` - RSF features ranked across all periods (includes both C-index types)
- `rsf_comparison_wide.csv` - RSF features in wide format for easy comparison
- `catboost_comparison_all_periods.csv` - CatBoost features ranked across all periods (includes both C-index types)
- `catboost_comparison_wide.csv` - CatBoost features in wide format
- `aorsf_comparison_all_periods.csv` - AORSF features ranked across all periods (includes both C-index types)
- `aorsf_comparison_wide.csv` - AORSF features in wide format
- `rsf_feature_overlap.csv` - Features common to all periods (RSF)
- `catboost_feature_overlap.csv` - Features common to all periods (CatBoost)
- `aorsf_feature_overlap.csv` - Features common to all periods (AORSF)
- `summary_statistics.csv` - Sample sizes, event rates, and **both C-index types** per period and method
- `cindex_comparison_all_methods.csv` - Combined C-index comparison (both types) across all methods and periods
- `cindex_td_comparison_wide.csv` - Time-dependent C-index comparison in wide format
- `cindex_ti_comparison_wide.csv` - Time-independent C-index comparison in wide format

## Usage

### Prerequisites

```r
# Required packages
install.packages(c("dplyr", "readr", "survival", "ranger", "tidyr", "purrr", "here", "riskRegression"))
install.packages("catboost")  # Optional but recommended
install.packages("aorsf")  # Optional but recommended for AORSF method
```

### Running the Script

```r
# From project root directory
source("replicate_20_features.R")
```

### Expected Runtime

- RSF feature selection: ~5-10 minutes per time period (depends on data size)
- CatBoost feature importance: ~10-20 minutes per time period
- AORSF feature importance: ~5-10 minutes per time period
- Total: ~60-120 minutes for all three methods across three periods

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
- **C-index**: Calculated using both time-dependent and time-independent methods

### AORSF Feature Importance

- **Method**: Accelerated Oblique Random Survival Forest (matching original study's final model)
- **Parameters**:
  - `n_tree = 100`
  - `na_action = 'impute_meanmode'`
- **Importance**: Uses negate method (`orsf_vi_negate`)
- **Selection**: Top 20 features by feature importance
- **C-index**: Calculated using both time-dependent and time-independent methods

## Model Performance Metrics

### C-index (Concordance Index)

The script calculates **both time-dependent and time-independent C-indexes** for each model:

#### Time-Dependent C-index
- **Method**: Matches `riskRegression::Score()` behavior (used in original study)
- **Evaluation**: At specific time horizon (default: 1 year)
- **Compares**: Patients with events before horizon vs patients at risk at horizon
- **Use**: Directly comparable to original study's reported C-index (~0.74)

#### Time-Independent C-index (Harrell's C)
- **Method**: Standard Harrell's C-index
- **Evaluation**: Uses all comparable pairs regardless of time
- **Compares**: All pairs where one patient has an event and another has a later time
- **Use**: General measure of discrimination across entire follow-up period

#### Interpretation
- C-index = 0.5: No discrimination (random)
- C-index = 1.0: Perfect discrimination
- C-index > 0.7: Good discrimination
- C-index > 0.8: Excellent discrimination

#### Output Columns
Each feature importance CSV file includes:
- `cindex_td`: Time-dependent C-index (comparable to original study)
- `cindex_ti`: Time-independent C-index (Harrell's C)

The C-index values are:
- Included in each feature importance CSV file (both types)
- Reported in the summary statistics table (both types)
- Printed during script execution for each model (both types)
- Available in separate comparison files for easy analysis

### Comparing Performance

- **Higher C-index** = better model discrimination
- **Time-dependent C-index**: Compare directly with original study results
- **Time-independent C-index**: Compare general discrimination across methods
- Compare RSF vs CatBoost vs AORSF C-index to see which method performs better
- Compare C-index across time periods to assess model stability

## Interpreting Results

### Feature Stability

- **High overlap** across time periods suggests robust features
- **Low overlap** suggests period-specific effects or instability

### Comparing RSF vs CatBoost vs AORSF

- **RSF**: Permutation-based importance (model-agnostic)
- **CatBoost**: Gain-based importance (model-specific)
- **AORSF**: Negate-based importance (matches original study's final model)
- Differences highlight which features are important for different model types
- **C-index comparison**: Compare discrimination performance between all three methods
- **Time-dependent C-index**: Use for comparison with original study (~0.74)
- **Time-independent C-index**: Use for general discrimination assessment

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

### CatBoost or AORSF Not Available

If CatBoost or AORSF fails:
- The script will continue with available methods
- Install CatBoost: `install.packages("catboost")`
- Install AORSF: `install.packages("aorsf")`
- Or skip unavailable methods - RSF will still run

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

