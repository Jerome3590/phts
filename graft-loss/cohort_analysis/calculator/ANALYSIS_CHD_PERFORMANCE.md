# Analysis: CHD Model Performance Decrease

## Summary

The CHD model showed a slight performance decrease after adding CHD-specific features:
- **Baseline**: AUC = 0.635 (95% CI: 0.564 - 0.701)
- **Improved**: AUC = 0.625 (95% CI: 0.557 - 0.678)
- **Change**: -0.010 AUC (small decrease, within confidence intervals)

## Root Cause Analysis

### 1. Too Many Sparse Categorical Features

**Problem**: 40+ CHD subtype variables were added, creating a high-dimensional sparse feature space.

**Evidence**:
- Top CHD subtype variables have very high importance:
  - `chd_lsvc`: 19.01
  - `chd_hb`: 14.88
  - `chd_alcapa`: 14.50
  - `chd_mart`: 13.90
  - `chd_raa`: 13.25
  - And 35+ more...

**Impact**: 
- Many patients have 0 for most CHD subtypes (sparse)
- Logistic regression struggles with many sparse categorical features
- Risk of overfitting to rare CHD subtypes

### 2. Multicollinearity

**Problem**: CHD subtypes are not independent - patients can have multiple subtypes.

**Evidence**: Multiple CHD subtypes show high importance simultaneously, suggesting they may be correlated or overlapping.

**Impact**: 
- Redundant information
- Unstable coefficient estimates
- Reduced model generalizability

### 3. Sample Size vs Feature Ratio

**Problem**: With 40+ CHD subtype features plus base features, the feature-to-sample ratio may be too high.

**Impact**:
- Increased variance in coefficient estimates
- Reduced model stability across MC-CV splits
- Higher risk of overfitting

## Recommendations

### Option 1: Feature Selection (Recommended)

Use LASSO or other regularization to select the most important CHD subtypes:

```r
# Use LASSO to select top CHD subtypes
# This will automatically select the most predictive ones
```

**Expected Impact**: Reduce from 40+ CHD subtypes to 5-10 most important ones, improving model stability.

### Option 2: CHD Subtype Aggregation

Group related CHD subtypes into clinically meaningful categories:

- **Single Ventricle**: chd_hlh, chd_sv, chd_dilv, etc.
- **Left Heart Obstruction**: chd_lvotoas, chd_shone, etc.
- **Right Heart Anomalies**: chd_raa, chd_papvr, etc.
- **Complex CHD**: chd_heter, chd_unk, etc.

**Expected Impact**: Reduce dimensionality while preserving clinical information.

### Option 3: Keep Only Top CHD Subtypes

Manually select the top 5-10 CHD subtypes by importance:

- `chd_lsvc` (19.01)
- `chd_hb` (14.88)
- `chd_alcapa` (14.50)
- `chd_mart` (13.90)
- `chd_raa` (13.25)
- `chd_dolv` (12.47)
- `chd_si` (12.30)

**Expected Impact**: Focus on most predictive subtypes, reduce noise.

### Option 4: Use Tree-Based Models

Switch to CatBoost or XGBoost for CHD model, which handle sparse categorical features better:

**Expected Impact**: Tree-based models can better handle many categorical features.

## Current Status

The CHD model still performs reasonably well (AUC = 0.625), and the decrease is small and within confidence intervals. However, implementing feature selection would likely improve performance and model interpretability.

## Comparison to Other Models

- **Combined Model**: Successfully improved (0.734 → 0.738) with `primary_etiology`
- **Myocardio Model**: Stable (0.657 → 0.657)
- **CHD Model**: Slight decrease (0.635 → 0.625), but with valuable insights about CHD subtypes

## Conclusion

The addition of CHD subtype variables provided valuable insights (identifying which subtypes are most predictive), but the large number of sparse features may be causing slight overfitting. Feature selection or aggregation would likely improve performance.
