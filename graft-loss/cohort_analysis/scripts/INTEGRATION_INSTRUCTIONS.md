# Integration Instructions for eGFR and WHO Calculations

This document explains how to integrate the eGFR and WHO growth curve calculations into the cohort analysis notebooks.

## Overview

Two new calculation scripts have been created:
1. `scripts/calculate_derived_features.R` - Main function to calculate eGFR, BMI, and WHO z-scores
2. `scripts/calculate_who_zscore.R` - Helper functions for WHO growth curve calculations

## Integration Steps

### Option 1: Source the Script (Recommended)

Add the following lines to your `prepare_modeling_data` function in each notebook, right after the variable exclusion step and before the median imputation step:

```r
# Calculate derived features: eGFR, BMI, and WHO growth curves
source(here("scripts", "calculate_derived_features.R"))
data <- calculate_derived_features(data)
```

**Location**: Insert this code after:
```r
exclude_all <- unique(c(exclude_exact, exclude_by_prefix))
data <- data %>% select(-any_of(exclude_all))
```

And before:
```r
# Median imputation for numeric variables
```

### Option 2: Inline Code

Alternatively, you can add the calculation code directly into the `prepare_modeling_data` function. See `scripts/calculate_derived_features.R` for the complete implementation.

## What Gets Calculated

### eGFR Calculation
- **Variable**: `egfr_tx`
- **Formula**: `0.413 * height_txpl / txcreat_r`
- **Requirements**: `height_txpl` and `txcreat_r` must be present

### BMI Calculation
- **Variable**: `bmi_txpl`
- **Formula**: `(weight_txpl / height_txpl^2) * 703`
- **Requirements**: `weight_txpl` and `height_txpl` must be present

### WHO Growth Curve Calculations
- **Variables**: 
  - `height_zscore_txpl`
  - `height_percentile_txpl`
  - `weight_zscore_txpl`
  - `weight_percentile_txpl`
- **Requirements**: 
  - Age (as `age_txpl` in years or `age_txpl_months` in months)
  - Sex (as `sex` or `rsex`)
  - `height_txpl` and `weight_txpl`

## Notebooks to Update

Update the `prepare_modeling_data` function in:
1. `graft_loss_clinical_cohort_survival.ipynb`
2. `graft_loss_clinical_cohort_event_classification.ipynb`
3. `graft_loss_clinical_cohort_analysis.ipynb`

## Testing

After integration, test the calculations by:
1. Running the data preparation step
2. Checking that `egfr_tx` and `bmi_txpl` are calculated correctly
3. Verifying WHO z-scores are calculated (if age and sex variables are available)

## Dependencies

The WHO calculations require the `zscorer` package for full functionality. Install it with:
```r
install.packages("zscorer")
```

If the package is not available, the code will still run but WHO calculations will be skipped with a warning.

