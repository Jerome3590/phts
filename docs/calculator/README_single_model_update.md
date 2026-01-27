# Single Model Update: Combined Model for All Cohorts

**Date:** January 26, 2026  
**Status:** ✅ Implemented

## Overview

Updated the model training and risk calculator to use a **single Combined model** for all cohorts (CHD, Combined, Myocardio). This simplifies deployment and ensures consistent predictions across all patient groups.

## Changes Made

### 1. Feature Engineering Updates

**File:** `graft-loss/cohort_analysis/calculator/run_shap_ffa_workflow.py`

Added new derived variables to `prepare_calculator_features()`:
- ✅ **vad_combined**: `txvad OR slvad` (VAD at transplant or listing)
- ✅ **vent_combined**: `txvent OR slvent OR ltxtrach OR hxtrach` (Mechanical ventilation at transplant or listing)
- ✅ **donor_weight_ratio**: `(weight_donor / weight_txpl) * 100` (Donor/recipient weight ratio)
- ✅ **donor_size_ratio**: `(height_donor / height_txpl) * 100` (Donor/recipient size ratio - height ratio)
- ✅ **chd_lat**: Composite laterality disorder from 8 CHD subtype variables (chd_dex, chd_si, chd_heter, chd_iivc, chd_bivc, chd_lsvc, chd_raa, chd_avd)

These match the feature engineering requirements from the risk calculator updates plan.

### 2. Model Training Updates

**File:** `graft-loss/cohort_analysis/calculator/train_python_models.py`

- Updated to **always train Combined model** regardless of `--cohort` parameter
- Added warning if user requests non-Combined cohort
- Single model is now used for all cohorts

**Usage:**
```bash
# Always trains Combined model
python train_python_models.py --cohort Combined
python train_python_models.py --cohort CHD  # Still trains Combined (with warning)
```

### 3. Lambda Function Updates

**File:** `graft-loss/cohort_analysis/calculator/risk_dashboard/phts_lambda_function.py`

**Key Changes:**

1. **Always uses Combined model**:
   - Added `MODEL_COHORT = "Combined"` constant
   - All model loading now uses `MODEL_COHORT` instead of requested cohort
   - Cohort parameter is only used for dashboard data (causal factors)

2. **Feature preparation for inference**:
   - Added `prepare_features_for_inference()` function
   - Creates derived variables (`vad_combined`, `vent_combined`, `donor_weight_ratio`, `ecmo_combined`)
   - Calculates `egfr_tx` from height and creatinine if not provided
   - Matches feature engineering in training

3. **Updated `predict_risk_survival()`**:
   - Always loads Combined model
   - Prepares features with derived variables before prediction
   - Returns both `model_cohort` (always "Combined") and `requested_cohort` (original parameter)

4. **Normalization**:
   - Uses `model_cohort` (Combined) for risk score normalization
   - Ensures consistent percentile calculations

### 4. Feature Validation Script

**File:** `graft-loss/cohort_analysis/calculator/validate_features.py` (NEW)

Created validation script to ensure training and inference features match:

**Usage:**
```bash
python validate_features.py --cohort Combined
```

**What it does:**
- Loads trained model and extracts feature names
- Re-runs training data preparation to get feature list
- Compares model features vs training features
- Reports missing features in either direction
- Saves validation results to JSON

**Output:**
- Validation status (PASSED/FAILED)
- Feature counts (model, training, common)
- Lists of missing features (if any)
- Results saved to `outputs/feature_validation.json`

## Feature Alignment

### Training Features (prepare_calculator_features)

The following derived variables are created during training:

1. **eGFR calculations**:
   - `egfr_tx`: 0.413 * height_txpl / txcreat_r
   - `egfr_listing`: 0.413 * height_listing / lcreat_r

2. **BMI**:
   - `bmi_txpl`: (weight_txpl / height_txpl²) * 703

3. **eGFR categories**:
   - `egfr_tx_cat`: severe/moderate/mild/normal
   - `egfr_listing_cat`: severe/moderate/mild/normal

4. **Dichotomous variables**:
   - `txbili_t_r_high`: > 1.5
   - `txbun_r_high`: > 30
   - `txsa_r_low`: < 3
   - `txalt_high`: > 90
   - `ecmo_combined`: txecmo OR slecmo
   - `vad_combined`: txvad OR slvad ✅ NEW
   - `vent_combined`: txvent OR slvent OR ltxtrach OR hxtrach ✅ NEW
   - `hxfonlvr_bin`: History of Fontan liver disease
   - `hxdysdia_bin`: History of dialysis

5. **Derived ratios**:
   - `egfr_change`: egfr_tx - egfr_listing
   - `donor_weight_ratio`: (weight_donor / weight_txpl) * 100 ✅ NEW
   - `donor_size_ratio`: (height_donor / height_txpl) * 100 ✅ NEW

### Inference Features (prepare_features_for_inference)

The Lambda function creates the same derived variables from user inputs:

1. **VAD combined**: `txvad OR slvad`
2. **Ventilation combined**: `txvent OR slvent OR ltxtrach OR hxtrach`
3. **ECMO combined**: `txecmo OR slecmo`
4. **Donor weight ratio**: `(weight_donor / weight_txpl) * 100`
5. **Donor size ratio**: `(height_donor / height_txpl) * 100`
6. **CHD laterality disorder**: `chd_dex OR chd_si OR chd_heter OR chd_iivc OR chd_bivc OR chd_lsvc OR chd_raa OR chd_avd`
7. **eGFR calculation**: `0.413 * height_txpl / txcreat_r` (if not provided)

## Validation

### Running Feature Validation

```bash
cd graft-loss/cohort_analysis/calculator
python validate_features.py --cohort Combined
```

This will:
1. Load the trained Combined model
2. Extract feature names from the model
3. Re-run training data preparation
4. Compare features between model and training
5. Report any mismatches

### Expected Output

```
Feature Validation Summary
================================================================================
Cohort: Combined
Model features: 150
Training features: 150
Common features: 150
Validation: PASSED
```

If validation fails, check:
- Are all derived variables being created?
- Are feature names consistent (case-sensitive)?
- Are leakage variables properly removed?

## Migration Notes

### For Existing Deployments

1. **Retrain models** with new derived variables:
   ```bash
   python train_python_models.py --cohort Combined
   ```

2. **Validate features**:
   ```bash
   python validate_features.py --cohort Combined
   ```

3. **Update Lambda container**:
   - Copy new model files to `lambda_dir_phts/models/Combined/`
   - Rebuild Docker container
   - Deploy updated Lambda function

4. **Update dashboard** (if needed):
   - Dashboard can still show cohort-specific causal factors
   - Risk predictions now use Combined model for all cohorts

### Backward Compatibility

- ✅ API endpoints remain unchanged
- ✅ Cohort parameter still accepted (for dashboard data)
- ✅ Response format unchanged (adds `model_cohort` field)
- ⚠️ Risk predictions now use Combined model (not cohort-specific)

## Testing

### Test Feature Preparation

```python
from risk_dashboard.phts_lambda_function import prepare_features_for_inference

# Test input
features = {
    "txvad": 1,
    "slvad": 0,
    "txvent": 0,
    "slvent": 1,
    "weight_donor": 80,
    "weight_txpl": 60,
    "height_txpl": 150,
    "txcreat_r": 0.8
}

# Prepare features
prepared = prepare_features_for_inference(features)

# Should have:
# - vad_combined: 1
# - vent_combined: 1
# - donor_weight_ratio: 133.33
# - donor_size_ratio: (if height_donor provided)
# - egfr_tx: 77.44
```

### Test Model Loading

```python
from risk_dashboard.phts_lambda_function import load_model, MODEL_COHORT

# Always loads Combined model
model = load_model(MODEL_COHORT, "catboost")
```

## Files Modified

1. ✅ `graft-loss/cohort_analysis/calculator/run_shap_ffa_workflow.py`
   - Added `vad_combined`, `vent_combined`, `donor_weight_ratio` to `prepare_calculator_features()`

2. ✅ `graft-loss/cohort_analysis/calculator/train_python_models.py`
   - Always trains Combined model regardless of `--cohort` parameter

3. ✅ `graft-loss/cohort_analysis/calculator/risk_dashboard/phts_lambda_function.py`
   - Added `MODEL_COHORT` constant
   - Added `prepare_features_for_inference()` function
   - Updated `predict_risk_survival()` to always use Combined model
   - Updated normalization to use model_cohort

4. ✅ `graft-loss/cohort_analysis/calculator/validate_features.py` (NEW)
   - Feature validation script

## Next Steps

1. **Retrain models** with new derived variables:
   ```bash
   python train_python_models.py --cohort Combined
   ```

2. **Run SHAP/FFA analysis**:
   ```bash
   python run_shap_ffa_workflow.py --cohort Combined --top-k 10
   ```

3. **Validate features**:
   ```bash
   python validate_features.py --cohort Combined
   ```

4. **Update Lambda deployment**:
   - Copy new models to Lambda container
   - Rebuild and deploy

## References

- Risk Calculator Updates Plan: `docs/calculator/README_risk_calculator_updates_plan.md`
- Feature Engineering: `graft-loss/cohort_analysis/calculator/run_shap_ffa_workflow.py` (prepare_calculator_features)
- Model Training: `graft-loss/cohort_analysis/calculator/train_python_models.py`
- Lambda Function: `graft-loss/cohort_analysis/calculator/risk_dashboard/phts_lambda_function.py`

---

**Last Updated:** January 26, 2026
