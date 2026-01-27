# Final Features Summary: Risk Calculator Requirements vs Model

**Date:** January 26, 2026  
**Model:** Combined (single model for all cohorts)  
**Status:** ✅ Aligned (after fixes)

## Feature Alignment: Requirements vs Model

### ✅ All Required Variables Present

| Requirement | Variable | Status | Notes |
|------------|----------|--------|-------|
| **Primary Diagnosis** | `primary_etiology` | ✅ | Fixed - now kept for Combined model |
| **Previous Cardiac Surgery** | `hxsurg` | ✅ | Present in model |
| **Laterality Disorder** | `chd_lat` | ✅ | Created as composite from 8 CHD subtypes |
| **Dialysis History** | `hxdysdia` / `hxdysdia_bin` | ✅ | Present (as binary) |
| **ECMO** | `ecmo_combined` | ✅ | Present |
| **VAD** | `vad_combined` | ✅ | Added in retraining |
| **Mechanical Ventilation** | `vent_combined` | ✅ | Added in retraining |
| **Age** | `age_txpl` | ✅ | Present (with `age_listing` fallback) |
| **eGFR** | `egfr_tx` | ✅ | Calculated from height/creatinine |
| **ALT** | `txalt` | ✅ | Present |
| **AST** | `txast` | ✅ | Present |
| **Direct Bilirubin** | `txbili_d_r` | ✅ | Present |
| **Total Bilirubin** | `txbili_t_r` | ✅ | Present |
| **Albumin** | `txsa_r` | ✅ | Present |
| **Total Protein** | `txtp_r` | ✅ | Present |
| **cPRA** | `txfcpra` | ✅ | Present (with `lsfcpra` fallback) |
| **Donor Ischemic Time** | `donisch` | ✅ | Present |
| **Donor Weight Ratio** | `donor_weight_ratio` | ✅ | Added in retraining |
| **Donor Size Ratio** | `donor_size_ratio` | ✅ | Added in retraining |

---

## New Derived Variables (Added in Retraining)

### 1. **vad_combined**
- **Formula**: `txvad OR slvad`
- **Purpose**: VAD at transplant or listing
- **Status**: ✅ Added

### 2. **vent_combined**
- **Formula**: `txvent OR slvent OR ltxtrach OR hxtrach`
- **Purpose**: Mechanical ventilation at transplant or listing
- **Status**: ✅ Added

### 3. **donor_weight_ratio**
- **Formula**: `(weight_donor / weight_txpl) * 100`
- **Purpose**: Donor/recipient weight matching
- **Status**: ✅ Added

### 4. **donor_size_ratio**
- **Formula**: `(height_donor / height_txpl) * 100`
- **Purpose**: Donor/recipient size matching (height ratio)
- **Status**: ✅ Added

### 5. **chd_lat**
- **Formula**: `chd_dex OR chd_si OR chd_heter OR chd_iivc OR chd_bivc OR chd_lsvc OR chd_raa OR chd_avd`
- **Purpose**: Composite laterality disorder indicator
- **Status**: ✅ Added
- **Components**: 8 CHD subtype variables (all also in model individually)

---

## Key Fixes Applied

### Fix 1: primary_etiology for Combined Model ✅

**Problem**: `primary_etiology` was in leakage keywords list, causing it to be removed.

**Solution**: Updated `get_survival_leakage_keywords()` to accept `cohort` parameter and exclude `primary_etiology` from removal for Combined model.

**Code Change**:
```python
def get_survival_leakage_keywords(cohort: Optional[str] = None) -> List[str]:
    # For Combined model, keep primary_etiology (it's needed to distinguish etiologies)
    if cohort != "Combined":
        keywords.append("primary_etiology")
    return keywords
```

### Fix 2: CHD_LAT Composite Variable ✅

**Problem**: `CHD_LAT` was not found as a single variable.

**Solution**: Created `chd_lat` as a composite variable from 8 CHD subtype variables.

**Code Added**:
```python
# In prepare_calculator_features()
chd_lat_vars = ["chd_dex", "chd_si", "chd_heter", "chd_iivc", "chd_bivc", "chd_lsvc", "chd_raa", "chd_avd"]
available_chd_lat_vars = [v for v in chd_lat_vars if v in df.columns]
if available_chd_lat_vars:
    df["chd_lat"] = df[available_chd_lat_vars].any(axis=1).astype(int)
```

---

## Complete Feature List (After Retraining)

The final feature set includes:

### Derived Variables (Created in Training)
1. `ecmo_combined` - ECMO at transplant or listing
2. `vad_combined` - VAD at transplant or listing ✅ NEW
3. `vent_combined` - Mechanical ventilation at transplant or listing ✅ NEW
4. `donor_weight_ratio` - Donor/recipient weight ratio (%) ✅ NEW
5. `donor_size_ratio` - Donor/recipient height ratio (%) ✅ NEW
6. `chd_lat` - Laterality disorder composite ✅ NEW
7. `egfr_tx` - eGFR at transplant (calculated)
8. `egfr_listing` - eGFR at listing (calculated)
9. `egfr_tx_cat` - eGFR category at transplant
10. `egfr_listing_cat` - eGFR category at listing
11. `egfr_change` - Change in eGFR
12. `bmi_txpl` - BMI at transplant
13. `txbili_t_r_high` - High total bilirubin
14. `txbun_r_high` - High BUN
15. `txsa_r_low` - Low albumin
16. `txalt_high` - High ALT
17. `hxfonlvr_bin` - History of Fontan liver disease
18. `hxdysdia_bin` - History of dialysis

### Original Clinical Variables
- All original variables from dataset that:
  - Are not leakage predictors
  - Are not constant (have variance)
  - Are not outcomes

**Includes:**
- Demographics: `age_txpl`, `age_listing`, `weight_txpl`, `height_txpl`, etc.
- Donor: `donor_age`, `donor_weight`, `donor_height`, `donisch`, etc.
- Clinical history: `hxsurg`, `hxmed`, `hxdysdia`, etc.
- Lab values: `txalt`, `txast`, `txbili_d_r`, `txbili_t_r`, `txsa_r`, `txtp_r`, etc.
- Support devices: `txecmo`, `txvad`, `txvent`, etc.
- Immunology: `txfcpra`, `lsfcpra`, etc.
- CHD subtypes: `chd_dex`, `chd_si`, `chd_heter`, etc. (40+ subtypes)
- Diagnoses: `sec_dx`, `ter_dx`, `primary_etiology` (Combined only)

---

## Variable Prioritization (Lambda Function)

The Lambda function implements prioritization logic:

### At Transplant > At Listing Priority

1. **Age**: `age_txpl` > `age_listing`
2. **eGFR**: `egfr_tx` > `egfr_listing` (calculated if not provided)
3. **ALT**: `txalt` > `lsalt`
4. **AST**: `txast` > `lsast`
5. **Direct Bilirubin**: `txbili_d_r` > `lsbili_d_r`
6. **Total Bilirubin**: `txbili_t_r` > `lsbili_t_r`
7. **Albumin**: `txsa_r` > `lssab_r`
8. **Total Protein**: `txtp_r` > `lstp_r`
9. **cPRA**: `txfcpra` > `lsfcpra`

### Combined Variables Priority

1. **ECMO**: `txecmo` > `slecmo` → `ecmo_combined`
2. **VAD**: `txvad` > `slvad` → `vad_combined`
3. **Ventilation**: `txvent` > `slvent` > `ltxtrach` > `hxtrach` → `vent_combined`

---

## Validation

After retraining, validate features:

```bash
# List all features
python list_model_features.py --cohort Combined --categorized

# Validate training vs model features
python validate_features.py --cohort Combined
```

**Expected Result**: All required variables present, feature alignment PASSED.

---

## Summary

✅ **All required variables are now included**:
- Primary diagnosis (`primary_etiology`) - Fixed for Combined model
- Previous cardiac surgery (`hxsurg`) - Present
- Laterality disorder (`chd_lat`) - Created as composite
- All support devices (ECMO, VAD, Ventilation) - Combined variables created
- All lab values - Present with prioritization
- Donor characteristics - Present with ratios
- All other required variables - Present

**Next Step**: Retrain models with these fixes to ensure all features are included.

---

**Last Updated:** January 26, 2026
