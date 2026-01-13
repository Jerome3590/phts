# Updated Codebase for PHTS Calculator Models

## Summary of Updates

The codebase has been updated to reflect the PHTS (Pediatric Heart Transplant Survival) calculator project structure:

### Key Changes

1. **Cohorts**: Changed from age bands to diagnostic cohorts
   - **Old**: Age bands (e.g., "13-24", "25-44")
   - **New**: Diagnostic cohorts (CHD, Combined, Myocardio)

2. **Features**: Changed from ICD/CPT/drug codes to clinical features
   - **Old**: `item_drug_*`, `item_ICD_*`, `item_CPT_*` (binary indicators)
   - **New**: Clinical features (eGFR, bilirubin, albumin, cardiac support, etc.)

3. **Feature Importance**: Uses aggregated feature importance from calculator models
   - Mean importance across MC-CV splits
   - From `outputs/models/{cohort}/importance_{cohort}_{model}.csv`

## Updated Files

### README Files
- `README_SHAP_FFA.md` - Updated to use diagnostic cohorts and clinical features
- `ffa_analysis/README.md` - Updated interaction analysis description

### Code Files
- `run_shap_ffa_workflow.py` - Updated comments to reference diagnostic cohorts
- `ffa_analysis/run_full_ffa_analysis.py` - Updated `get_model_features_for_causal_analysis()` to use clinical features

## Clinical Features Used

The PHTS calculator models use the following clinical feature categories:

### Kidney Function
- `egfr_tx`, `egfr_listing` - Estimated GFR at transplant/listing
- `egfr_tx_cat`, `egfr_listing_cat` - eGFR categories (severe/moderate/mild/normal)
- `hxdysdia_bin` - History of dialysis
- `egfr_change` - Change in eGFR from listing to transplant

### Liver Function
- `txbili_t_r` - Total bilirubin at transplant
- `txbili_t_r_high` - High bilirubin indicator (>1.5)
- `txalt`, `txalt_high` - ALT at transplant (high >90)
- `txast` - AST at transplant

### Nutrition
- `txpalb_r` - Pre-albumin at transplant
- `txsa_r`, `txsa_r_low` - Serum albumin (low <3)
- `txtp_r` - Total protein at transplant
- `bmi_txpl` - BMI at transplant

### Cardiac Support
- `txvad` - VAD at transplant
- `txecmo`, `slecmo`, `ecmo_combined` - ECMO indicators

### Respiratory
- `txvent` - Ventilation at transplant
- `hxtrach`, `ltxtrach` - Tracheostomy indicators

### Demographics
- `age_listing`, `age_txpl` - Age at listing/transplant
- `chd_hlh`, `chd_*` - CHD subtypes (CHD cohort only)

### PRA (Panel Reactive Antibodies)
- `lsfcpra`, `lsfprab`, `lsfprat` - PRA at listing
- `txfcpra` - PRA at transplant

## Feature Importance Source

Feature importance is loaded from calculator model outputs:
- Path: `outputs/models/{cohort}/importance_{cohort}_{model}.csv`
- Format: CSV with columns `feature` and `importance`
- Aggregation: Mean importance across 25 MC-CV splits

## Interaction Analysis

The interaction analysis now identifies clinical feature combinations:
- **Pairs**: e.g., `egfr_tx_cat|txbili_t_r_high` (kidney + liver function)
- **Triplets**: e.g., `txecmo|egfr_tx_cat|txsa_r_low` (cardiac support + kidney + nutrition)

These interactions measure synergy/antagonism effects on graft loss risk.

## Notes

- The `run_full_ffa_analysis.py` file still contains references to the old project structure (opioid_ed, age bands) but is not actively used for the PHTS calculator workflow
- The main workflow is `run_shap_ffa_workflow.py` which has been updated
- All feature importance comes from aggregated calculator model outputs, not from separate SHAP analysis steps
