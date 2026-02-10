# Calculator Workflow Notebook Structure Check

## Overview
This document verifies that the single top-features model (Combined_top) has all required steps in the calculator workflow notebook.

## Required Steps for Top Model (`Combined_top`)

### ✅ Top Model (top 15 causal/importance features)
1. **Training** (Section 3) - ✓
   - Run: `python train_python_models.py --top_features_only`
   - Trains in `outputs/models/Combined_top/`
   - Generates feature importance files, saves best_model.txt

2. **SHAP/FFA Analysis** (Section 4) - ✓
   - Run with `--model-variant top`
   - Outputs to `outputs/shap_ffa/Combined_top/`
   - Generates dashboard_data.json and top_causal_factors.csv

3. **Feature Importance** (Section 5a) - ✓
   - Checks `outputs/models/Combined_top/` (or `Combined/`) for importance files
   - Displays top features

4. **Results Inspection** (Section 5) - ✓
   - Checks `outputs/shap_ffa/Combined_top/dashboard_data.json`
   - Displays top causal factors

## Verification Checklist

### Training Steps
- [x] Section 3: Top model training (`--top_features_only` → Combined_top)
- [x] Feature importance CSV and best_model.txt in Combined_top/

### SHAP/FFA Analysis Steps
- [x] Section 4: SHAP/FFA with `--model-variant top`
- [x] Output to `outputs/shap_ffa/Combined_top/`
- [x] dashboard_data.json and top_causal_factors.csv generated
- [x] SHAP on test set, rules from XGBoost JSON, causal responsibility

### Feature Importance & Results
- [x] Section 5a: Checks Combined_top (or Combined/) for importance files
- [x] Section 5: Loads dashboard_data.json from Combined_top, displays causal factors

## Output Directory Structure

After running the workflow:

```
outputs/
├── models/
│   └── Combined_top/
│       ├── best_model.txt
│       ├── importance_*.csv or mc_cv_*_feature_importance.csv
│       └── [model files .cbm, .ubj, final_model_json/]
└── shap_ffa/
    └── Combined_top/
        ├── dashboard_data.json
        ├── top_causal_factors.csv
        └── [other analysis files]
```

## Dashboard Integration

Single model: **Risk Calculator** and **Causal Analysis** tabs use `Combined_top/` only.

## Notes

- Feature importance is automatically computed during training (saved as CSV files)
- SHAP/FFA analysis computes additional feature importance from SHAP values
- Causal responsibility combines rule frequencies with SHAP importance
- All results are saved to separate directories for each model variant
