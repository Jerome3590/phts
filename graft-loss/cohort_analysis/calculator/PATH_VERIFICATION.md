# Path Verification Summary

This document verifies that all outputs are saved with correct paths and visualizations are properly mapped to consume these outputs.

## Output Directory Structure

### Models
- **Baseline Model**: `outputs/models/{COHORT}_base/`
  - Model files: `*.cbm`, `*.ubj`
  - Best model info: `best_model.txt`
  - Feature names: `feature_names.json`
  - Feature importance: `importance_*.csv`
  - Model JSON: `final_model_json/{COHORT}_final_model_xgboost.json`

- **Enhanced Model**: `outputs/models/{COHORT}_enhanced/`
  - Same structure as baseline

### Dashboard Data (SHAP/FFA Outputs)
- **Baseline Model**: `outputs/shap_ffa/{COHORT}_base/`
  - `dashboard_data.json` - Complete dashboard data structure
  - `top_causal_factors.csv` - Top K causal factors
  - `combined_shap_importance.csv` - Combined SHAP importance scores
  - `analysis_report.txt` - Text summary report

- **Enhanced Model**: `outputs/shap_ffa/{COHORT}_enhanced/`
  - Same structure as baseline

- **Comparison Visualizations**: `outputs/shap_ffa/{COHORT}_comparison_top_{TOP_K}_factors.png`
  - Comparison plot saved at shap_ffa root level

## Verified Components

### 1. run_shap_ffa_workflow.py ✅
- **Output Directory**: Correctly uses `outputs/shap_ffa/{model_cohort}/` where `model_cohort` is determined by `get_model_cohort_name()`
- **Model Variant Handling**: Properly handles `--model-variant base` and `--model-variant enhanced`
- **Dashboard Output**: Saves `dashboard_data.json` to correct location: `output_dir / 'dashboard_data.json'`

### 2. calculator_workflow_interactive.py ✅
- **Model Paths**: Correctly references `outputs/models/{COHORT}_base/` and `outputs/models/{COHORT}_enhanced/`
- **Dashboard Paths**: Correctly references `outputs/shap_ffa/{COHORT}_base/dashboard_data.json` and `outputs/shap_ffa/{COHORT}_enhanced/dashboard_data.json`
- **Visualization Paths**: All visualization paths are correct

### 3. calculator_workflow.ipynb ✅
- **Model Paths**: Correctly references variant-specific directories
- **Dashboard Paths**: Correctly loads from `outputs/shap_ffa/{COHORT}_base/` and `outputs/shap_ffa/{COHORT}_enhanced/`
- **Visualization Paths**: 
  - Individual plots: `outputs/shap_ffa/{COHORT}_base/top_{TOP_K}_factors.png`
  - Individual plots: `outputs/shap_ffa/{COHORT}_enhanced/top_{TOP_K}_factors.png`
  - Comparison plot: `outputs/shap_ffa/{COHORT}_comparison_top_{TOP_K}_factors.png`

### 4. prepare_lambda_dir_phts.py ✅ (FIXED)
- **Models**: Now correctly handles both variant (`{cohort}_base`, `{cohort}_enhanced`) and non-variant structures
- **Dashboard Data**: Now correctly copies from variant directories to lambda directory
- **Feature Metadata**: Now correctly extracts from variant-specific dashboard_data.json files
- **Validation**: Updated to check for variant-specific directories

### 5. phts_lambda_function.py ✅
- **Model Loading**: Uses `MODEL_BASE_PATH / model_cohort` where `model_cohort` can be `{cohort}_base` or `{cohort}_enhanced`
- **Dashboard Loading**: Uses `DASHBOARD_DATA_PATH / model_cohort / "dashboard_data.json"` where `model_cohort` is determined by variant
- **Auto-detection**: Correctly auto-detects enhanced vs base variants

## Path Mapping Summary

| Component | Source Path | Destination/Usage Path | Status |
|-----------|-------------|------------------------|--------|
| Baseline Models | `outputs/models/Combined_base/` | Lambda: `models/Combined_base/` | ✅ |
| Enhanced Models | `outputs/models/Combined_enhanced/` | Lambda: `models/Combined_enhanced/` | ✅ |
| Baseline Dashboard | `outputs/shap_ffa/Combined_base/dashboard_data.json` | Lambda: `dashboard_data/Combined_base/dashboard_data.json` | ✅ |
| Enhanced Dashboard | `outputs/shap_ffa/Combined_enhanced/dashboard_data.json` | Lambda: `dashboard_data/Combined_enhanced/dashboard_data.json` | ✅ |
| Notebook Visualizations | `outputs/shap_ffa/{COHORT}_base/top_{TOP_K}_factors.png` | Loaded by notebook | ✅ |
| Comparison Plot | `outputs/shap_ffa/{COHORT}_comparison_top_{TOP_K}_factors.png` | Saved by notebook | ✅ |

## Key Fixes Applied

1. **prepare_lambda_dir_phts.py**: Updated to handle model variant directories (`Combined_base`, `Combined_enhanced`)
   - Models: Now checks for variant directories
   - Dashboard Data: Now copies from variant directories
   - Feature Metadata: Now extracts from variant-specific files
   - Validation: Now checks for variant-specific structures

## Verification Checklist

- [x] Models saved to correct variant directories
- [x] Dashboard data saved to correct variant directories
- [x] Interactive workflow script uses correct paths
- [x] Notebook uses correct paths for loading and saving
- [x] Lambda preparation script handles variants correctly
- [x] Lambda function loads from correct variant paths
- [x] Visualizations save to and load from correct paths

## Notes

- For `Combined` cohort, both `_base` and `_enhanced` variants are expected
- For `CHD` and `Myocardio` cohorts, the script checks for both variant and non-variant structures (backward compatibility)
- All paths use `CALCULATOR_DIR` as the base, which is `graft-loss/cohort_analysis/calculator/`
- Lambda directory structure matches what the lambda function expects
