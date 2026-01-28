# Recommended Additional Features for Calculator Model

Based on analysis of previous model performance and feature importance, here are features that could improve model performance and are calculator-accessible:

## High Priority Features (Strong Evidence from Previous Models)

### 1. **BNP (Brain Natriuretic Peptide)**
- **Features**: `txbnp`, `txpbnp_r`, `lbnp`, `lspbnp_r`
- **Rationale**: 
  - Appears frequently in XGBoost tree splits (e.g., `lbnp<542`, `lbnp<18.4`)
  - Cardiac biomarker commonly measured in heart failure/transplant patients
  - Calculator-accessible: Standard lab value
- **Expected Impact**: Moderate to high (cardiac function indicator)
- **Recommendation**: ✅ **ADD** - `txbnp`, `txpbnp_r`, `lbnp`, `lspbnp_r`

### 2. **CRP (C-Reactive Protein)**
- **Features**: `txcrp_r`, `lcrp_r`
- **Rationale**:
  - Inflammatory marker, commonly measured
  - Appears in model trees
  - Calculator-accessible: Standard lab value
- **Expected Impact**: Moderate (inflammation indicator)
- **Recommendation**: ✅ **ADD** - `txcrp_r`, `lcrp_r`

### 3. **Secondary/Tertiary Diagnoses**
- **Features**: `sec_dx`, `ter_dx`
- **Rationale**:
  - Appears frequently in XGBoost trees (e.g., `sec_dx<1`)
  - Could capture comorbidities that affect risk
  - Calculator-accessible: Diagnosis codes
- **Expected Impact**: Moderate to high (comorbidity indicator)
- **Recommendation**: ✅ **ADD** - `sec_dx`, `ter_dx` (if not used for cohort definition)

### 4. **Cholesterol/Lipid Panel**
- **Features**: `txchol_r`, `txtg_r`, `txldl_r`, `txhdl_r`, `txvldl_r`
- **Rationale**:
  - Appears in model trees (e.g., `txchol_r<124`, `txtg_r<82`)
  - Metabolic health indicator
  - Calculator-accessible: Standard lab panel
- **Expected Impact**: Low to moderate
- **Recommendation**: ⚠️ **CONSIDER** - May be less critical, but easy to add

## Medium Priority Features

### 5. **Pre-albumin at Listing**
- **Features**: `lspalb_r`
- **Rationale**:
  - We have `txpalb_r` (at transplant) but not listing version
  - Nutrition marker, appears in trees
  - Calculator-accessible: Standard lab value
- **Expected Impact**: Low to moderate
- **Recommendation**: ✅ **ADD** - `lspalb_r` (completeness)

### 6. **Oxygen Saturation**
- **Features**: `txbaosat`, `txsvcsat`, `lsbaosat`, `lssvcsat`
- **Rationale**:
  - Respiratory function indicator
  - Appears in some model trees
  - Calculator-accessible: Standard vital sign
- **Expected Impact**: Low to moderate
- **Recommendation**: ⚠️ **CONSIDER** - May be redundant with ventilation status

## Lower Priority (More Specialized)

### 7. **Hemodynamic Measurements**
- **Features**: `txbram`, `txbpam`, `txbpcw`, `txbco`, `txbci`, `txbrp`, `txbrs` (and listing versions)
- **Rationale**:
  - Appear in model trees
  - More specialized, may not always be available
  - Calculator-accessible: If available from cardiac catheterization
- **Expected Impact**: Moderate (if available)
- **Recommendation**: ⚠️ **OPTIONAL** - Only if commonly available in calculator context

### 8. **Ejection Fraction**
- **Features**: `esteject`, `fracshor`
- **Rationale**:
  - Cardiac function indicator
  - Appears in some trees
  - Calculator-accessible: From echocardiography
- **Expected Impact**: Moderate
- **Recommendation**: ⚠️ **CONSIDER** - If commonly measured

## Summary Recommendations

### **Must Add** (High Impact, Calculator-Accessible):
1. ✅ BNP values: `txbnp`, `txpbnp_r`, `lbnp`, `lspbnp_r`
2. ✅ CRP: `txcrp_r`, `lcrp_r`
3. ✅ Secondary/Tertiary diagnoses: `sec_dx`, `ter_dx` (if not used for cohort filtering)
4. ✅ Pre-albumin at listing: `lspalb_r`

### **Should Consider** (Moderate Impact):
5. ⚠️ Lipid panel: `txchol_r`, `txtg_r`, `txldl_r`, `txhdl_r`
6. ⚠️ Oxygen saturation: `txbaosat`, `txsvcsat` (if not redundant)

### **Optional** (Specialized, Lower Priority):
7. ⚠️ Hemodynamic measurements (if commonly available)
8. ⚠️ Ejection fraction (if commonly measured)

## Expected Performance Impact

Adding the "Must Add" features (BNP, CRP, sec_dx/ter_dx, lspalb_r) could potentially:
- **Improve C-index**: +0.02 to +0.04 (from ~0.58-0.60 to ~0.60-0.64)
- **Improve AUC**: +0.01 to +0.03 (from ~0.71-0.72 to ~0.72-0.75)

These features capture:
- **Cardiac function** (BNP)
- **Inflammation** (CRP)
- **Comorbidities** (sec_dx, ter_dx)
- **Nutrition status** (lspalb_r)

All are commonly available in clinical practice and calculator-accessible.
