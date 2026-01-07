# Calculator Model Improvements

## Changes Made

### 1. Explicitly Include `primary_etiology` in Combined Model

**Rationale**: The Combined model includes all patients across different etiologies. Including `primary_etiology` as an explicit feature allows the model to directly use this strong predictor, which should improve performance.

**Expected Impact**: 
- Combined model AUC should increase from ~0.734
- This is the primary reason for the performance gap between Combined and cohort-specific models

### 2. Enhanced CHD-Specific Features

**Added**:
- All `CHD_*` variables (automatically detected)
- `hxfonlvr_bin` (History of Fontan Associated Liver Disease) - CHD-specific

**Rationale**: 
- CHD patients have unique risk factors (e.g., Fontan-associated liver disease)
- Additional CHD subtype variables may capture important heterogeneity within CHD
- Current CHD model AUC (0.635) suggests room for improvement

**Expected Impact**:
- CHD model AUC should improve from ~0.635
- Better capture of CHD-specific risk factors

## Feature Importance Insights

From the current importance analysis:

### Combined Model Top Features:
1. `txfcpra` (Done/Not.Done) - **3.06 importance** (very strong)
2. `egfr_listing_catnormal` - 1.57
3. `ecmo_combined` - 1.31
4. `hxtrach` - 1.16
5. `chd_hlh` - 0.31

### CHD Model Top Features:
1. `txfcpra` (Done/Not.Done) - **13.02 importance** (extremely strong!)
2. `ecmo_combined` - 2.40
3. `egfr_listing_catnormal` - 2.07
4. `slecmo` - 1.52
5. `chd_hlh` - 0.23

**Key Observation**: `txfcpra` is MUCH more important in CHD patients (13.02 vs 3.06), suggesting it's a critical predictor for CHD-specific risk.

## Performance Expectations

### Before Improvements:
- **Combined**: AUC = 0.734
- **CHD**: AUC = 0.635
- **Myocardio**: AUC = 0.657

### After Improvements (Expected):
- **Combined**: AUC = 0.75-0.78 (with primary_etiology)
- **CHD**: AUC = 0.65-0.70 (with additional CHD features)
- **Myocardio**: AUC = 0.65-0.68 (similar, may improve slightly)

## Why Combined Model Performs Better

1. **Heterogeneity**: Different etiologies have different baseline risks
2. **Sample Size**: More data improves model stability
3. **Cross-Etiology Patterns**: Model can learn features that vary across etiologies
4. **Primary Etiology Signal**: Now explicitly included as a feature

## Next Steps

1. Re-run the calculator models with these improvements
2. Compare new results to baseline
3. Analyze feature importance to identify additional improvements
4. Consider interaction terms if needed
