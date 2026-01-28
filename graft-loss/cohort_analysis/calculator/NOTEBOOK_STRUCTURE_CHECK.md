# Calculator Workflow Notebook Structure Check

## Overview
This document verifies that both Baseline and Enhanced models have all required steps in the calculator workflow notebook.

## Required Steps for Each Model Variant

### ✅ Baseline Model (`Combined_base`)
1. **Training** (Section 3a) - ✓ Present
   - Trains models in `outputs/models/Combined_base/`
   - Generates feature importance files
   - Saves best_model.txt

2. **SHAP/FFA Analysis** (Section 4a) - ✓ Updated
   - Uses `--model-variant base` explicitly
   - Outputs to `outputs/shap_ffa/Combined_base/`
   - Generates dashboard_data.json with causal factors
   - Computes feature importance from SHAP values

3. **Feature Importance** (Section 5a) - ✓ Updated
   - Checks `outputs/models/Combined_base/` for importance files
   - Displays top features for baseline model

4. **Results Inspection** (Section 5) - ✓ Updated
   - Checks `outputs/shap_ffa/Combined_base/dashboard_data.json`
   - Displays top causal factors for baseline model

### ✅ Enhanced Model (`Combined_enhanced`)
1. **Training** (Section 3b) - ✓ Present
   - Trains models in `outputs/models/Combined_enhanced/`
   - Generates feature importance files
   - Saves best_model.txt

2. **SHAP/FFA Analysis** (Section 4b) - ✓ Updated
   - Uses `--model-variant enhanced` explicitly
   - Outputs to `outputs/shap_ffa/Combined_enhanced/`
   - Generates dashboard_data.json with causal factors
   - Computes feature importance from SHAP values

3. **Feature Importance** (Section 5a) - ✓ Updated
   - Checks `outputs/models/Combined_enhanced/` for importance files
   - Displays top features for enhanced model

4. **Results Inspection** (Section 5) - ✓ Updated
   - Checks `outputs/shap_ffa/Combined_enhanced/dashboard_data.json`
   - Displays top causal factors for enhanced model

## Verification Checklist

### Training Steps
- [x] Section 3a: Baseline model training (Combined_base)
- [x] Section 3b: Enhanced model training (Combined_enhanced)
- [x] Both generate feature importance CSV files
- [x] Both save best_model.txt

### SHAP/FFA Analysis Steps
- [x] Section 4a: Baseline SHAP/FFA (uses --model-variant base)
- [x] Section 4b: Enhanced SHAP/FFA (uses --model-variant enhanced)
- [x] Both output to correct directories (Combined_base/ and Combined_enhanced/)
- [x] Both generate dashboard_data.json
- [x] Both compute SHAP values on test set
- [x] Both extract rules from XGBoost JSON
- [x] Both calculate causal responsibility

### Feature Importance
- [x] Section 5a: Checks both Combined_base and Combined_enhanced
- [x] Displays feature importance for both variants
- [x] Shows top features for each model

### Results Inspection
- [x] Section 5: Checks both Combined_base and Combined_enhanced
- [x] Displays causal factors for both variants
- [x] Shows summary statistics for both models

### Visualizations
- [x] Section 6: Comparison visualizations for both models
- [x] Side-by-side bar charts
- [x] Difference plots
- [x] Summary tables

### Export Summary
- [ ] Section 5c: Should check both variants (needs update)
  - Currently only checks COHORT (Combined)
  - Should check Combined_base and Combined_enhanced separately

## Output Directory Structure

After running the complete workflow, you should have:

```
outputs/
├── models/
│   ├── Combined_base/
│   │   ├── best_model.txt
│   │   ├── importance_*.csv (for each model type)
│   │   ├── feature_names.json
│   │   └── [model files]
│   └── Combined_enhanced/
│       ├── best_model.txt
│       ├── importance_*.csv (for each model type)
│       ├── feature_names.json
│       └── [model files]
└── shap_ffa/
    ├── Combined_base/
    │   ├── dashboard_data.json
    │   ├── top_causal_factors.csv
    │   └── [other analysis files]
    └── Combined_enhanced/
        ├── dashboard_data.json
        ├── top_causal_factors.csv
        └── [other analysis files]
```

## Dashboard Integration

Both models' results are used in the risk dashboard:
- **Baseline Model Tab**: Uses `Combined_base/` models and `Combined_base/` dashboard data
- **Extended Model Tab**: Uses `Combined_enhanced/` models and `Combined_enhanced/` dashboard data
- **Model Comparison Tab**: Compares both models side-by-side

## Notes

- Feature importance is automatically computed during training (saved as CSV files)
- SHAP/FFA analysis computes additional feature importance from SHAP values
- Causal responsibility combines rule frequencies with SHAP importance
- All results are saved to separate directories for each model variant
