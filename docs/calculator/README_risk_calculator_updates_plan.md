# Risk Calculator Update Implementation Plan

## Overview

This document outlines the implementation plan for updating the PHTS Risk Calculator to:
1. Add disclaimers and assumptions about model constraints
2. Prioritize "at transplant" variables over "at listing" variables
3. Reorganize input variables according to clinical workflow
4. Add new variables (donor/recipient weight ratio, enhanced donor ischemic time handling)
5. Improve user experience with better prompts and variable prioritization

**Last Updated**: January 26, 2026  
**Status**: Partially implemented — backend defaults added; UI (disclaimers, prompts) not yet implemented (see below)

### Implementation status (as of last update)

| Requirement | Status | Notes |
|-------------|--------|--------|
| Disclaimer: donor-recipient size ratio 70–200% at top of calculator | **Implemented** | Blue info box at top of `phts_dashboard.html` |
| Disclaimer: DONISCH &lt; 240 min when not given | **Implemented** | Amber warning box at top of `phts_dashboard.html`; backend defaults `donisch` to 180 min when missing |
| Prompt user for most recent (at transplant) values | **Implemented** | Note box updated: “Enter the most recent patient values below (at transplant is preferred over at listing)” |
| Model prioritize at transplant over at listing | **Implemented** | Backend uses at-transplant vars; UI note and labels (e.g. “at Transplant”) reflect prioritization |
| Backend default DONISCH when missing | **Implemented** | `phts_lambda_function.prepare_features_for_inference()` sets `donisch = 180` if not provided |

---

## 1. User Interface Updates

### 1.1 Disclaimers and Assumptions

**Location**: Top of Risk Calculator tab, before cohort selector

**Content**:
1. **Donor-Recipient Size Ratio Assumption**
   - Text: "This calculator assumes the donor-recipient weight ratio is between 70-200%. If the actual ratio falls outside this range, results may be less accurate."
   - Display: Info box (blue background, similar to existing info-box style)

2. **Donor Ischemic Time Assumption**
   - Text: "If donor ischemic time is not provided, the model will assume it is less than 240 minutes (4 hours). Please enter the most recent donor ischemic time when available."
   - Display: Info box (yellow/amber background for warning)

**Implementation**:
- Add two new info boxes in `phts_dashboard.html`
- Style with appropriate colors (blue for info, amber for warning)
- Position before cohort selector

### 1.2 Variable Input Reorganization

**New Structure**: Organize inputs by clinical workflow priority

#### Section 1: Primary Diagnosis
- **Primary Diagnosis** (dropdown)
  - Options: Congenital Heart Disease, Dilated Cardiomyopathy, Myocarditis, Other
  - If "Congenital Heart Disease" selected:
    - Show: "Previous Cardiac Surgery" (HxSURG) - Yes/No
    - Show: "Laterality Disorder" (CHD_LAT) - Yes/No
      - Hover tooltip: "Laterality disorders include: [list 7 conditions]"
      - Tooltip content: "Heterotaxy, Situs Inversus, Situs Ambiguus, Left Atrial Isomerism, Right Atrial Isomerism, Asplenia, Polysplenia"

#### Section 2: Demographics & Age
- **Age at Transplant** (age_txpl) - years
  - Priority: age_txpl > age_listing
  - If not provided, fallback to age_listing
  - Alternative: Age_under_2 (binary) if preferred

#### Section 3: Cardiac Support
- **ECMO** (ecmo_combined)
  - Priority: txecmo > slecmo
  - Display: "ECMO (at transplant or listing)"
  - Yes/No dropdown

- **VAD** (vad_combined - new derived variable)
  - Priority: txvad > slvad
  - Display: "VAD (at transplant or listing)"
  - Yes/No dropdown
  - **Backend Logic**: Create `vad_combined = txvad OR slvad` (similar to ecmo_combined)

- **Mechanical Ventilation** (vent_combined - new derived variable)
  - Priority: txvent > slvent > ltxtrach > hxtrach
  - Display: "Mechanical Ventilation (at transplant or listing)"
  - Yes/No dropdown
  - **Backend Logic**: Create `vent_combined = txvent OR slvent OR ltxtrach OR hxtrach`

#### Section 4: Renal Function
- **Dialysis History** (HXDYSDIA)
  - Display: "History of Dialysis (ever)"
  - Yes/No dropdown
  - Note: Use "ever" history as per requirements

- **eGFR at Transplant** (egfr_tx)
  - **Option A**: Direct input
    - Label: "eGFR at Transplant (mL/min/1.73m²)"
    - Number input
  - **Option B**: Calculated from components (preferred)
    - Sub-fields:
      - Patient Height at Transplant (cm) - height_txpl
      - BUN at Transplant (mg/dL) - txbun_r
      - Creatinine at Transplant (mg/dL) - txcreat_r
    - Auto-calculate eGFR using Schwartz formula: `egfr_tx = 0.413 × height_txpl / txcreat_r`
    - Display calculated value
    - Allow manual override if pre-calculated

#### Section 5: Liver Function
- **ALT at Transplant** (TXALT) - U/L
  - Priority: txalt > lsalt
- **AST at Transplant** (TXAST) - U/L
  - Priority: txast > lsast
- **Direct Bilirubin at Transplant** (TXBILI_D_R) - mg/dL
  - Priority: txbili_d_r > lsbili_d_r
- **Total Bilirubin at Transplant** (TXBILI_T_R) - mg/dL
  - Priority: txbili_t_r > lsbili_t_r

#### Section 6: Nutrition
- **Serum Albumin at Transplant** (TXSA_R) - g/dL
  - Priority: txsa_r > lssab_r
- **Total Protein at Transplant** (TXTP_R) - g/dL (optional, lower priority)
  - Priority: txtp_r > lstp_r

#### Section 7: Immunology
- **cPRA at Transplant** (TXFCPRA) - %
  - Priority: txfcpra > lsfcpra
  - Display: "Flow Cytometry PRA (cPRA) at Transplant (%)"
  - Note: "If Class 1 (LSFPRAB) or Class 2 (LSFPRAT) specific PRA available, total cPRA should also be available"

#### Section 8: Donor Characteristics
- **Donor Ischemic Time** (DONISCH) - minutes
  - Display: "Donor Ischemic Time (minutes)"
  - Default: If not provided, assume < 240 minutes
  - Validation: Warn if > 240 minutes (outside model assumption)

- **Donor/Recipient Weight Ratio** (NEW - donor_weight_ratio)
  - Display: "Donor/Recipient Weight Ratio (%)"
  - Calculation: `(weight_donor / weight_txpl) × 100`
  - Input options:
    - **Option A**: Direct ratio input (percentage)
    - **Option B**: Component inputs:
      - Donor Weight (kg) - weight_donor
      - Recipient Weight at Transplant (kg) - weight_txpl
      - Auto-calculate ratio
  - Validation: Warn if ratio < 70% or > 200% (outside model assumption)

---

## 2. Backend Logic Updates

### 2.1 Variable Prioritization Logic

**Location**: `phts_lambda_function.py` - `prepare_features()` function

**Implementation**: Create helper function to prioritize variables

```python
def prioritize_variable(features: Dict[str, Any], 
                        tx_var: str, 
                        listing_var: str, 
                        default_value: Any = None) -> Any:
    """
    Prioritize 'at transplant' variable over 'at listing' variable.
    
    Args:
        features: Dictionary of input features
        tx_var: Variable name at transplant (e.g., 'txfcpra')
        listing_var: Variable name at listing (e.g., 'lsfcpra')
        default_value: Default value if neither is available
    
    Returns:
        Prioritized value
    """
    # Priority: tx_var > listing_var > default_value
    if tx_var in features and features[tx_var] is not None:
        return features[tx_var]
    elif listing_var in features and features[listing_var] is not None:
        return features[listing_var]
    else:
        return default_value
```

**Variables Requiring Prioritization**:

1. **Age**: `age_txpl` > `age_listing`
2. **eGFR**: `egfr_tx` > `egfr_listing` (if calculated, use calculated)
3. **ALT**: `txalt` > `lsalt`
4. **AST**: `txast` > `lsast`
5. **Bilirubin (Direct)**: `txbili_d_r` > `lsbili_d_r`
6. **Bilirubin (Total)**: `txbili_t_r` > `lsbili_t_r`
7. **Albumin**: `txsa_r` > `lssab_r`
8. **Total Protein**: `txtp_r` > `lstp_r`
9. **cPRA**: `txfcpra` > `lsfcpra`

### 2.2 New Derived Variables

**Location**: `phts_lambda_function.py` - `prepare_features()` function

**Variables to Create**:

1. **vad_combined** (similar to existing ecmo_combined)
   ```python
   vad_combined = 1 if (features.get('txvad') == 1 or features.get('slvad') == 1) else 0
   ```

2. **vent_combined** (new)
   ```python
   vent_combined = 1 if (
       features.get('txvent') == 1 or 
       features.get('slvent') == 1 or 
       features.get('ltxtrach') == 1 or 
       features.get('hxtrach') == 1
   ) else 0
   ```

3. **donor_weight_ratio** (new)
   ```python
   if 'weight_donor' in features and 'weight_txpl' in features:
       if features['weight_txpl'] > 0:
           donor_weight_ratio = (features['weight_donor'] / features['weight_txpl']) * 100
       else:
           donor_weight_ratio = None
   ```

4. **donisch_default** (handling)
   ```python
   # If donisch not provided, assume < 240 minutes
   if 'donisch' not in features or features['donisch'] is None:
       # Set to a value representing < 240 minutes (e.g., 180 minutes = 3 hours)
       features['donisch'] = 180  # or use median from training data
   ```

### 2.3 eGFR Calculation

**Location**: Frontend (JavaScript) and/or Backend (Python)

**Frontend Implementation** (preferred for immediate feedback):
```javascript
function calculateEGFR(height, creatinine) {
    if (height && creatinine && creatinine > 0) {
        return 0.413 * height / creatinine;
    }
    return null;
}

// Auto-calculate when height or creatinine changes
document.getElementById('height_txpl').addEventListener('input', updateEGFR);
document.getElementById('txcreat_r').addEventListener('input', updateEGFR);

function updateEGFR() {
    const height = parseFloat(document.getElementById('height_txpl').value);
    const creat = parseFloat(document.getElementById('txcreat_r').value);
    const egfr = calculateEGFR(height, creat);
    if (egfr) {
        document.getElementById('egfr_tx').value = egfr.toFixed(2);
    }
}
```

**Backend Fallback** (if frontend calculation fails):
- Calculate in `prepare_features()` if egfr_tx not provided but components are available

---

## 3. Model Updates

### 3.1 Variable Availability Check

**Action**: Verify all required variables are available in trained models

**Variables Status**:
- ✅ `donisch` - Already in models (confirmed via grep)
- ✅ `ecmo_combined` - Already exists (created in `prepare_calculator_features()`)
- ❌ `vad_combined` - **NOT in models** - Must add to training (Phase 0)
- ❌ `vent_combined` - **NOT in models** - Must add to training (Phase 0)
- ❓ `CHD_LAT` - Need to verify if in models
- ❌ `donor_weight_ratio` - **NOT in models** - Must add to training (Phase 0)

**Decision Tree**:
1. ✅ If variable exists in model → Use directly (`donisch`, `ecmo_combined`)
2. ❌ If variable doesn't exist → **MUST RETRAIN MODELS** (Phase 0)
   - `vad_combined`: Add to `prepare_calculator_features()`, retrain
   - `vent_combined`: Add to `prepare_calculator_features()`, retrain
   - `donor_weight_ratio`: Add to `prepare_calculator_features()`, retrain
3. ⚠️ If variable is new and not in model → **Cannot use until models retrained**
   - Models won't use variables they weren't trained with
   - Lambda will ignore missing features (set to 0/default)

### 3.2 Model Retraining Requirements

**⚠️ CRITICAL: Models MUST be retrained with new derived variables**

**Why Retraining is Required**:
- Models are trained with a specific feature set
- If `vad_combined`, `vent_combined`, or `donor_weight_ratio` are not in the training data, models won't have learned to use them
- Even though these are derived from existing variables, models need to be trained with them to benefit from the combined representation
- The Lambda function maps user inputs to model feature names - if a feature doesn't exist in the model, it's ignored

**New Variables to Add to Training**:
1. `vad_combined`: Created from `txvad` OR `slvad`
2. `vent_combined`: Created from `txvent` OR `slvent` OR `ltxtrach` OR `hxtrach`
3. `donor_weight_ratio`: Calculated from `weight_donor` / `weight_txpl` × 100

**Retraining Steps**:
1. ✅ Update `prepare_calculator_features()` in `run_shap_ffa_workflow.py` to create new variables
2. ✅ Retrain models for all cohorts (CHD, Combined, Myocardio)
3. ✅ Verify new variables appear in model feature lists
4. ✅ Update model files in Lambda container
5. ✅ Update feature metadata files
6. ✅ Rebuild and deploy Lambda container

**Note**: Base variables (`txvad`, `slvad`, `txvent`, etc.) will still be in models, but combined variables may provide better predictive power.

---

## 4. Implementation Steps

### Phase 0: Model Retraining (CRITICAL - MUST DO FIRST)

**⚠️ IMPORTANT**: Before implementing UI changes, we must retrain the models with new derived variables. The models need to be trained with these variables for them to be used in predictions.

**Files to Modify**:
- `graft-loss/cohort_analysis/calculator/run_shap_ffa_workflow.py` - `prepare_calculator_features()` function

**Tasks**:
1. ✅ Add `vad_combined` derivation to `prepare_calculator_features()`
   ```python
   # VAD combined (txvad OR slvad)
   if "txvad" in df.columns and "slvad" in df.columns:
       df["vad_combined"] = ((df["txvad"] == 1) | (df["slvad"] == 1)).astype(int)
       logger.info("Created vad_combined")
   ```

2. ✅ Add `vent_combined` derivation to `prepare_calculator_features()`
   ```python
   # Ventilation combined (txvent OR slvent OR ltxtrach OR hxtrach)
   vent_vars = ["txvent", "slvent", "ltxtrach", "hxtrach"]
   available_vent_vars = [v for v in vent_vars if v in df.columns]
   if available_vent_vars:
       df["vent_combined"] = df[available_vent_vars].any(axis=1).astype(int)
       logger.info(f"Created vent_combined from {available_vent_vars}")
   ```

3. ✅ Add `donor_weight_ratio` calculation to `prepare_calculator_features()`
   ```python
   # Donor/Recipient Weight Ratio
   if "weight_donor" in df.columns and "weight_txpl" in df.columns:
       mask = df["weight_txpl"].notna() & (df["weight_txpl"] > 0)
       df["donor_weight_ratio"] = np.nan
       df.loc[mask, "donor_weight_ratio"] = (
           (df.loc[mask, "weight_donor"] / df.loc[mask, "weight_txpl"]) * 100
       )
       logger.info("Created donor_weight_ratio")
   ```

4. ✅ Retrain all models for all cohorts:
   ```bash
   python train_python_models.py --cohort Combined
   python train_python_models.py --cohort CHD
   python train_python_models.py --cohort Myocardio
   ```

5. ✅ Verify new variables are in trained models:
   - Check model feature names
   - Verify `vad_combined`, `vent_combined`, `donor_weight_ratio` appear in feature lists

6. ✅ Update model files in Lambda container:
   - Copy new model files to `lambda_dir_phts/models/`
   - Rebuild Docker container
   - Deploy updated Lambda function

**Estimated Time**: 4-6 hours (depending on model training time)

**Why This Must Come First**:
- Models are trained with a specific set of features
- If we add new variables to the UI but models weren't trained with them, the models won't use them
- The Lambda function maps user inputs to model feature names - if a feature doesn't exist in the model, it will be ignored (set to 0/default)
- To actually benefit from `vad_combined`, `vent_combined`, and `donor_weight_ratio`, models must be retrained with these variables

**Alternative Approach** (NOT RECOMMENDED):
- We could create derived variables at inference time in Lambda
- But models won't use them unless they were trained with them
- Models would still use base variables (`txvad`, `slvad`, etc.) which may be less predictive
- This defeats the purpose of creating combined variables

---

### Phase 1: UI Updates (Frontend)

**Files to Modify**:
- `graft-loss/cohort_analysis/calculator/risk_dashboard/phts_dashboard.html`

**Tasks**:
1. ✅ Add disclaimer boxes at top
2. ✅ Reorganize form sections according to new structure
3. ✅ Add new input fields:
   - Primary diagnosis dropdown
   - CHD-specific fields (HxSURG, CHD_LAT with tooltip)
   - Dialysis history
   - Enhanced liver function inputs
   - Donor weight ratio input
4. ✅ Add eGFR calculation logic (JavaScript)
5. ✅ Add variable prioritization hints in UI
6. ✅ Update form validation

**Estimated Time**: 4-6 hours

### Phase 2: Backend Logic (Lambda Function)

**Files to Modify**:
- `graft-loss/cohort_analysis/calculator/risk_dashboard/phts_lambda_function.py`

**Tasks**:
1. ✅ Create `prioritize_variable()` helper function
2. ✅ Update `prepare_features()` to use prioritization
3. ✅ Add derived variable creation:
   - `vad_combined`
   - `vent_combined`
   - `donor_weight_ratio`
4. ✅ Add `donisch` default handling (< 240 minutes)
5. ✅ Add eGFR calculation fallback (if not provided)
6. ✅ Update feature metadata handling

**Estimated Time**: 3-4 hours

### Phase 3: Variable Verification

**Tasks**:
1. ✅ Check which variables exist in current models
2. ✅ Verify CHD_LAT variable availability
3. ✅ Test variable prioritization logic
4. ✅ Verify derived variables work with models

**Estimated Time**: 2-3 hours

### Phase 4: Testing

**Tasks**:
1. ✅ Test UI with all new inputs
2. ✅ Test variable prioritization (at transplant > at listing)
3. ✅ Test eGFR calculation
4. ✅ Test donor weight ratio calculation
5. ✅ Test default values (donisch < 240, weight ratio 70-200%)
6. ✅ Test with missing values
7. ✅ Integration testing with Lambda function
8. ✅ End-to-end testing

**Estimated Time**: 4-6 hours

### Phase 5: Documentation Updates

**Files to Update**:
- `docs/calculator/README_dashboard.md`
- `docs/calculator/README_final_models.md`
- `graft-loss/cohort_analysis/calculator/risk_dashboard/README_DASHBOARD.md`

**Tasks**:
1. ✅ Update variable list
2. ✅ Document prioritization logic
3. ✅ Document new variables
4. ✅ Update user guide with new workflow

**Estimated Time**: 2-3 hours

### Phase 6: Deployment

**Tasks**:
1. ✅ Update Lambda container with new code
2. ✅ Deploy updated HTML to S3
3. ✅ Test production deployment
4. ✅ Monitor for errors

**Estimated Time**: 2-3 hours

---

## 5. Variable Mapping Reference

### Current Variables → New Priority Variables

| Category | At Transplant Variable | At Listing Variable | Priority Logic |
|----------|------------------------|---------------------|----------------|
| Age | `age_txpl` | `age_listing` | age_txpl > age_listing |
| eGFR | `egfr_tx` | `egfr_listing` | egfr_tx > egfr_listing |
| ALT | `txalt` | `lsalt` | txalt > lsalt |
| AST | `txast` | `lsast` | txast > lsast |
| Bilirubin (D) | `txbili_d_r` | `lsbili_d_r` | txbili_d_r > lsbili_d_r |
| Bilirubin (T) | `txbili_t_r` | `lsbili_t_r` | txbili_t_r > lsbili_t_r |
| Albumin | `txsa_r` | `lssab_r` | txsa_r > lssab_r |
| Total Protein | `txtp_r` | `lstp_r` | txtp_r > lstp_r |
| cPRA | `txfcpra` | `lsfcpra` | txfcpra > lsfcpra |
| ECMO | `txecmo` | `slecmo` | ecmo_combined = txecmo OR slecmo |
| VAD | `txvad` | `slvad` | vad_combined = txvad OR slvad (NEW) |
| Ventilation | `txvent` | `slvent`, `ltxtrach`, `hxtrach` | vent_combined = txvent OR slvent OR ltxtrach OR hxtrach (NEW) |

### New Variables

| Variable | Type | Description | Calculation |
|----------|------|-------------|-------------|
| `vad_combined` | Binary | VAD at transplant or listing | txvad OR slvad |
| `vent_combined` | Binary | Mechanical ventilation at transplant or listing | txvent OR slvent OR ltxtrach OR hxtrach |
| `donor_weight_ratio` | Numeric | Donor/recipient weight ratio (%) | (weight_donor / weight_txpl) × 100 |

---

## 6. Validation Rules

### Input Validation

1. **Donor Ischemic Time (DONISCH)**
   - If not provided: Default to 180 minutes (< 240)
   - If provided: Warn if > 240 minutes (outside model assumption)
   - Unit: minutes

2. **Donor/Recipient Weight Ratio**
   - If not provided: Assume within 70-200% range
   - If provided: Warn if < 70% or > 200%
   - Calculation: (weight_donor / weight_txpl) × 100

3. **eGFR**
   - If calculated: Use Schwartz formula
   - If provided directly: Use as-is
   - Validation: Typical range 60-120 mL/min/1.73m²

4. **Age**
   - Priority: age_txpl > age_listing
   - If neither provided: Show error or use default

---

## 7. Testing Checklist

### Functional Testing

- [ ] Disclaimer boxes display correctly
- [ ] Primary diagnosis selection works
- [ ] CHD-specific fields appear/disappear correctly
- [ ] CHD_LAT tooltip displays 7 conditions
- [ ] Variable prioritization works (at transplant > at listing)
- [ ] eGFR auto-calculation works
- [ ] Donor weight ratio calculation works
- [ ] Default values applied correctly (donisch < 240, weight ratio 70-200%)
- [ ] Validation warnings display for out-of-range values
- [ ] Form submission works with new variables
- [ ] Risk calculation works with prioritized variables

### Edge Cases

- [ ] Missing "at transplant" variable falls back to "at listing"
- [ ] Missing both "at transplant" and "at listing" uses default
- [ ] eGFR calculation with missing components
- [ ] Donor weight ratio with missing weight values
- [ ] CHD patient without laterality disorder
- [ ] Non-CHD patient (CHD fields hidden)

### Integration Testing

- [ ] Frontend → Backend variable mapping correct
- [ ] Derived variables created correctly in backend
- [ ] Model receives all required variables
- [ ] Risk calculation produces valid results
- [ ] Causal factors display correctly

---

## 8. Risk Assessment

### Low Risk
- UI updates (frontend only)
- Adding new input fields
- Documentation updates

### Medium Risk
- Variable prioritization logic
- Derived variable creation
- Default value handling

### High Risk
- Model compatibility with new variables
- Variable mapping between frontend and backend
- Integration with existing Lambda function

### Mitigation Strategies
1. Test variable prioritization thoroughly
2. Verify model compatibility before deployment
3. Implement fallback logic for missing variables
4. Add comprehensive logging for debugging
5. Deploy to staging environment first

---

## 9. Open Questions / Decisions Needed

1. **eGFR Input Method**: 
   - Option A: Direct input only
   - Option B: Component inputs with auto-calculation (preferred)
   - **Decision**: Option B (component inputs with auto-calculation)

2. **Donor Weight Ratio Input Method**:
   - Option A: Direct ratio input
   - Option B: Component inputs (donor weight, recipient weight)
   - **Decision**: Option B (component inputs with auto-calculation)

3. **CHD_LAT Tooltip Content**:
   - Need to confirm the 7 specific laterality disorder conditions
   - **Action**: Verify with clinical team

4. **Model Retraining**:
   - Do we need to retrain models with new derived variables?
   - **Decision**: ✅ **YES - REQUIRED**. Models must be retrained with `vad_combined`, `vent_combined`, and `donor_weight_ratio` for these variables to be used in predictions. This is Phase 0 and must be done first.

5. **Age Variable**:
   - Use `age_txpl` (continuous) or `Age_under_2` (binary)?
   - **Decision**: Use `age_txpl` (continuous) with prioritization

6. **Dialysis History**:
   - "Ever" history confirmed, but need to verify variable name
   - **Action**: Verify `HXDYSDIA` is the correct variable

---

## 10. Timeline Estimate

**Total Estimated Time**: 21-31 hours

**Breakdown**:
- Phase 0 (Model Retraining): 4-6 hours ⚠️ **MUST DO FIRST**
- Phase 1 (UI): 4-6 hours
- Phase 2 (Backend): 3-4 hours
- Phase 3 (Verification): 2-3 hours
- Phase 4 (Testing): 4-6 hours
- Phase 5 (Documentation): 2-3 hours
- Phase 6 (Deployment): 2-3 hours

**Recommended Approach**: 
- **Week 1**: Phase 0 (Model Retraining) - CRITICAL FIRST STEP
- **Week 2**: Phases 1-2 (UI + Backend)
- **Week 3**: Phases 3-4 (Verification + Testing)
- **Week 4**: Phases 5-6 (Documentation + Deployment)

---

## 11. Success Criteria

1. ✅ Disclaimers display correctly
2. ✅ All new variables are collectable via UI
3. ✅ Variable prioritization works (at transplant > at listing)
4. ✅ Derived variables created correctly
5. ✅ Risk calculations produce valid results
6. ✅ User experience improved (clearer workflow)
7. ✅ Documentation updated
8. ✅ No regression in existing functionality

---

## Appendix A: Laterality Disorder Conditions

**CHD_LAT Tooltip Content** (to be confirmed):
1. Heterotaxy
2. Situs Inversus
3. Situs Ambiguus
4. Left Atrial Isomerism
5. Right Atrial Isomerism
6. Asplenia
7. Polysplenia

**Note**: Verify exact list with clinical team.

---

## Appendix B: Variable Name Reference

### PHTS Database Variable Names

| Display Name | Variable Name | Notes |
|-------------|---------------|-------|
| Previous Cardiac Surgery | `HxSURG` or `hxsurg` | History of surgery |
| Laterality Disorder | `CHD_LAT` or `chd_lat` | Composite variable |
| Dialysis History | `HXDYSDIA` or `hxdysdia` | Ever history |
| ECMO Combined | `ecmo_combined` | txecmo OR slecmo |
| VAD Combined | `vad_combined` | txvad OR slvad (NEW) |
| Ventilation Combined | `vent_combined` | txvent OR slvent OR ltxtrach OR hxtrach (NEW) |
| Donor Ischemic Time | `DONISCH` or `donisch` | Minutes |
| Donor Weight Ratio | `donor_weight_ratio` | (weight_donor / weight_txpl) × 100 (NEW) |

---

**Document Status**: Draft - Ready for Review  
**Next Steps**: 
1. Review with clinical team
2. Confirm variable names and tooltip content
3. Begin Phase 1 implementation
