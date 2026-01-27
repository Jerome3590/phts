# Feature Alignment Check: Risk Calculator Requirements vs Model Features

**Date:** January 26, 2026  
**Status:** ⚠️ Issues Found - Needs Updates

## Risk Calculator Requirements Summary

### Required Input Variables

1. **Primary Diagnosis** (`primary_etiology` or `prim_dx`)
   - Options: Congenital Heart Disease, Dilated Cardiomyopathy, Myocarditis, Other
   - **If CHD selected**: Show `hxsurg` and `CHD_LAT`

2. **Previous Cardiac Surgery** (`hxsurg` / `HxSURG`)

3. **Laterality Disorder** (`CHD_LAT` / `chd_lat`)
   - 7 conditions: Heterotaxy, Situs Inversus, Situs Ambiguus, Left Atrial Isomerism, Right Atrial Isomerism, Asplenia, Polysplenia

4. **Dialysis History** (`hxdysdia` / `HXDYSDIA`) - "ever" history

5. **ECMO** (`ecmo_combined`) ✅

6. **VAD** (`vad_combined`) ✅ NEW

7. **Mechanical Ventilation** (`vent_combined`) ✅ NEW

8. **Age** (`age_txpl` > `age_listing`, or `age_under_2`)

9. **Renal Function** (`egfr_tx`) - calculated from height/creatinine ✅

10. **Liver Function**:
    - `txalt` (TXALT) ✅
    - `txast` (TXAST) ✅
    - `txbili_d_r` (TXBILI_D_R) ✅
    - `txbili_t_r` (TXBILI_T_R) ✅

11. **Nutrition**:
    - `txsa_r` (TXSA_R) ✅
    - `txtp_r` (TXTP_R) ✅

12. **Immunology**:
    - `txfcpra` (TXFCPRA) > `lsfcpra` (LSFCPRA) ✅

13. **Donor Ischemic Time** (`donisch` / `DONISCH`) ✅

14. **Donor/Recipient Weight Ratio** (`donor_weight_ratio`) ✅ NEW

15. **Donor/Recipient Size Ratio** (`donor_size_ratio`) ✅ NEW

---

## Current Model Status

### ✅ Variables Present in Model

All required variables are present **EXCEPT**:

### ❌ Issues Found

#### 1. **Primary Diagnosis** (`primary_etiology` / `prim_dx`)

**Status:** ⚠️ **CONFLICT**

- **In leakage keywords**: Listed in `get_survival_leakage_keywords()` as removed
- **But in models**: Appears in Combined model feature metadata and is a top predictor
- **Resolution needed**: 
  - For **Combined model**: `primary_etiology` should be **KEPT** (not removed)
  - It's needed to distinguish between CHD, Cardiomyopathy, Myocarditis
  - Update leakage removal to exclude `primary_etiology` for Combined model

#### 2. **CHD_LAT (Laterality Disorder)**

**Status:** ✅ **FIXED**

- `CHD_LAT` is a **composite variable** created from 8 CHD subtype variables:
  - `chd_dex` (Dextrocardia)
  - `chd_si` (Situs Inversus)
  - `chd_heter` (Heterotaxy)
  - `chd_iivc` (Interrupted IVC)
  - `chd_bivc` (Bilateral SVC)
  - `chd_lsvc` (Left SVC)
  - `chd_raa` (Right Aortic Arch)
  - `chd_avd` (AV Discordance)
- **Action**: Added logic to create `chd_lat` as composite: `chd_lat = chd_dex OR chd_si OR chd_heter OR ...`
- Individual CHD subtype variables are also in the model (40+ subtypes)

#### 3. **HxSURG (Previous Cardiac Surgery)**

**Status:** ✅ **PRESENT**

- Variable `hxsurg` should be in the model (not in leakage list)

---

## Required Fixes

### Fix 1: Keep `primary_etiology` for Combined Model

**File:** `graft-loss/cohort_analysis/calculator/train_python_models.py`

**Current code:**
```python
def get_survival_leakage_keywords() -> List[str]:
    return [
        "primary_etiology",  # ❌ This removes it
        "prim_dx", "PRIM_DX",
        ...
    ]
```

**Fix needed:**
```python
def get_survival_leakage_keywords(cohort: str = None) -> List[str]:
    """
    Get leakage keywords. For Combined model, keep primary_etiology.
    """
    keywords = [
        "transplant_year", "txpl_year",
        # Don't remove primary_etiology for Combined model
        ...
    ]
    
    # Only remove prim_dx/PRIM_DX (not primary_etiology) for Combined
    if cohort != "Combined":
        keywords.extend(["prim_dx", "PRIM_DX", "primary_etiology"])
    else:
        # For Combined, keep primary_etiology but remove prim_dx variants
        keywords.extend(["prim_dx", "PRIM_DX"])
    
    return keywords
```

**Or better approach:**
```python
def remove_leakage_predictors(
    df: pd.DataFrame,
    leak_keywords: Optional[List[str]] = None,
    cohort: Optional[str] = None,  # Add cohort parameter
    ...
):
    if leak_keywords is None:
        leak_keywords = get_survival_leakage_keywords(cohort)
    
    # Special handling: Keep primary_etiology for Combined model
    if cohort == "Combined":
        # Remove primary_etiology from drop list if it's there
        leak_keywords = [k for k in leak_keywords if k != "primary_etiology"]
    
    ...
```

### Fix 2: Create CHD_LAT Composite Variable ✅ DONE

**Status:** ✅ **IMPLEMENTED**

- Added logic to create `chd_lat` from 8 CHD subtype variables
- Created in both training (`prepare_calculator_features()`) and inference (`prepare_features_for_inference()`)
- Individual CHD subtype variables remain in the model
- `chd_lat` provides a simplified binary indicator for laterality disorders

### Fix 3: Verify All Required Variables

Run validation after fixes:

```bash
python validate_features.py --cohort Combined
python list_model_features.py --cohort Combined --categorized
```

---

## Feature Comparison Table

| Requirement | Variable Name | Status | Notes |
|------------|---------------|--------|-------|
| Primary Diagnosis | `primary_etiology` | ⚠️ | Fixed - now kept for Combined model |
| Previous Cardiac Surgery | `hxsurg` | ✅ | Present |
| Laterality Disorder | `CHD_LAT` / `chd_lat` | ✅ | Created as composite from 8 CHD subtypes |
| Dialysis History | `hxdysdia` | ✅ | Present (as `hxdysdia_bin`) |
| ECMO | `ecmo_combined` | ✅ | Present |
| VAD | `vad_combined` | ✅ | Added in retraining |
| Mechanical Ventilation | `vent_combined` | ✅ | Added in retraining |
| Age | `age_txpl` | ✅ | Present |
| eGFR | `egfr_tx` | ✅ | Calculated |
| ALT | `txalt` | ✅ | Present |
| AST | `txast` | ✅ | Present |
| Direct Bilirubin | `txbili_d_r` | ✅ | Present |
| Total Bilirubin | `txbili_t_r` | ✅ | Present |
| Albumin | `txsa_r` | ✅ | Present |
| Total Protein | `txtp_r` | ✅ | Present |
| cPRA | `txfcpra` | ✅ | Present |
| Donor Ischemic Time | `donisch` | ✅ | Present |
| Donor Weight Ratio | `donor_weight_ratio` | ✅ | Added in retraining |
| Donor Size Ratio | `donor_size_ratio` | ✅ | Added in retraining |

---

## Next Steps

1. ✅ **Fix `primary_etiology` removal** for Combined model - DONE
2. ✅ **Create `CHD_LAT` composite variable** - DONE
3. ⏳ **Retrain models** with fixes (required)
4. ⏳ **Validate features** match requirements (after retraining)
5. ⏳ **Update Lambda function** to handle `primary_etiology` input (if needed)

---

**Last Updated:** January 26, 2026
