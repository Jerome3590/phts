# Path Verification Summary

This document verifies that all outputs are saved with correct paths and visualizations are properly mapped to consume these outputs.

## Output Directory Structure

### Models
- **Top Model** (single model): `outputs/models/Combined_top/`
  - Model files: `*.cbm`, `*.ubj`
  - Best model info: `best_model.txt`
  - Feature names from model / feature_metadata
  - Feature importance: `importance_*.csv` or `mc_cv_*_feature_importance.csv`
  - Model JSON: `final_model_json/` (XGBoost JSON for FFA)

### Dashboard Data (SHAP/FFA Outputs)
- **Top Model**: `outputs/shap_ffa/Combined_top/`
  - `dashboard_data.json` - Complete dashboard data structure
  - `top_causal_factors.csv` - Top K causal factors
  - `combined_shap_importance.csv` - Combined SHAP importance scores
  - `analysis_report.txt` - Text summary report

## Verified Components

### 1. run_shap_ffa_workflow.py ✅
- **Output Directory**: Correctly uses `outputs/shap_ffa/{model_cohort}/` where `model_cohort` is from `get_model_cohort_name()`
- **Model Variant Handling**: Supports `--model-variant top` (default), `base`, `enhanced`, `auto`
- **Dashboard Output**: Saves `dashboard_data.json` to correct location: `output_dir / 'dashboard_data.json'`

### 2. calculator_workflow.ipynb ✅
- **Model Paths**: References `outputs/models/Combined_top/`
- **Dashboard Paths**: Loads from `outputs/shap_ffa/Combined_top/dashboard_data.json`
- **Visualization Paths**: Plots under `outputs/shap_ffa/Combined_top/` as needed

### 3. prepare_lambda_dir_phts.py ✅
- **Models**: Copies only `Combined_top/` to Lambda
- **Dashboard Data**: Copies from `outputs/shap_ffa/Combined_top/`
- **Feature Metadata**: Extracted from `Combined_top` dashboard_data.json
- **Validation**: Checks for `Combined_top` directory

### 4. phts_lambda_function.py ✅
- **Model Loading**: Uses `MODEL_BASE_PATH / model_cohort` with `model_cohort` = `Combined_top`
- **Dashboard Loading**: Uses `DASHBOARD_DATA_PATH / Combined_top / "dashboard_data.json"`
- **Default variant**: Single model; API uses `Combined_top` only

## Path Mapping Summary

| Component | Source Path | Destination/Usage Path | Status |
|-----------|-------------|------------------------|--------|
| Top Model | `outputs/models/Combined_top/` | Lambda: `models/Combined_top/` | ✅ |
| Top Dashboard | `outputs/shap_ffa/Combined_top/dashboard_data.json` | Lambda: `dashboard_data/Combined_top/dashboard_data.json` | ✅ |
| Notebook Visualizations | `outputs/shap_ffa/Combined_top/` | Loaded by notebook | ✅ |

## Key Fixes Applied

1. **prepare_lambda_dir_phts.py**: Single model only; copies `Combined_top/` (models, dashboard data, feature metadata). Validation checks for `Combined_top`.

## Verification Checklist

- [x] Models saved to correct variant directories
- [x] Dashboard data saved to correct variant directories
- [x] Interactive workflow script uses correct paths
- [x] Notebook uses correct paths for loading and saving
- [x] Lambda preparation script handles variants correctly
- [x] Lambda function loads from correct variant paths
- [x] Visualizations save to and load from correct paths

## Notes

- For `Combined` cohort, only `Combined_top` (top 15 causal features) is expected
- For `CHD` and `Myocardio` cohorts, the script checks for both variant and non-variant structures (backward compatibility)
- All paths use `CALCULATOR_DIR` as the base, which is `graft-loss/cohort_analysis/calculator/`
- Lambda directory structure matches what the lambda function expects
