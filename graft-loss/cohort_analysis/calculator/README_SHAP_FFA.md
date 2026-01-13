# SHAP + FFA Integration for PHTS Calculator Models

This document describes the integrated SHAP and FFA analysis workflow for the PHTS (Pediatric Heart Transplant Survival) calculator models.

## Overview

The workflow combines:
1. **SHAP Analysis**: Feature importance from CatBoost and XGBoost survival models using aggregated feature importance (mean across MC-CV splits)
2. **FFA Analysis**: Formal Feature Attribution using combined SHAP values for clinical features
3. **Dashboard Outputs**: Top K causal factors for risk dashboard

## Cohorts

The PHTS calculator uses **diagnostic cohorts** (not age bands):
- **CHD**: Congenital Heart Disease cohort
- **Combined**: All primary diagnoses (includes `primary_etiology` as feature)
- **Myocardio**: Cardiomyopathy and Myocarditis cohort

## Clinical Features

The models use **clinical features** (not ICD/CPT/drug codes):
- **Kidney function**: eGFR, creatinine, dialysis history, eGFR categories
- **Liver function**: Bilirubin, ALT, AST
- **Nutrition**: Albumin, pre-albumin, total protein, BMI
- **Cardiac support**: VAD, ECMO
- **Respiratory**: Ventilation, tracheostomy
- **Demographics**: Age at listing/transplant, CHD subtypes
- **PRA**: Panel reactive antibodies

## Workflow

### Step 1: Train Calculator Models

First, train the calculator models using Python:

```bash
cd graft-loss/cohort_analysis/calculator
python train_python_models.py --cohort Combined
```

This generates:
- `outputs/models/{cohort}/best_model.txt` - Best model selection
- `outputs/models/{cohort}/catboost_model.cbm` - CatBoost model binary
- `outputs/models/{cohort}/xgboost_model.ubj` - XGBoost model binary
- `outputs/models/{cohort}/xgboost_rf_model.ubj` - XGBoost RF model binary
- `outputs/models/{cohort}/final_model_json/{cohort}_final_model_xgboost.json` - XGBoost JSON for FFA
- `outputs/models/{cohort}/final_model_json/{cohort}_final_model_xgboost_rf.json` - XGBoost RF JSON for FFA

### Step 2: Run SHAP + FFA Workflow

Run the integrated workflow:

```bash
python run_shap_ffa_workflow.py --cohort Combined --top-k 10
```

Options:
- `--cohort`: Cohort name (CHD, Combined, Myocardio)
- `--top-k`: Number of top causal factors to extract (default: 10)
- `--weight-catboost`: Weight for CatBoost importance (default: 0.6)
- `--weight-xgboost`: Weight for XGBoost importance (default: 0.4)
- `--output-dir`: Custom output directory (default: outputs/shap_ffa/{cohort})

### Step 3: Review Results

Results are saved to `outputs/shap_ffa/{cohort}/`:

- `dashboard_data.json` - Complete dashboard data structure
- `top_causal_factors.csv` - Top K causal factors with scores
- `combined_shap_importance.csv` - Combined SHAP importance for all features
- `ffa_causal_factors.csv` - FFA causal analysis results
- `analysis_report.txt` - Human-readable summary report

## Output Structure

### dashboard_data.json

```json
{
  "cohort": "Combined",
  "timestamp": "2024-01-15T10:30:00",
  "top_causal_factors": [
    {
      "feature": "feature_name",
      "causal_responsibility": 0.85,
      "shap_importance": 0.82,
      "rank": 1
    }
  ],
  "summary": {
    "total_features": 150,
    "top_k": 10,
    "mean_importance": 0.15,
    "max_importance": 0.85,
    "top_feature": "feature_name",
    "top_feature_importance": 0.85
  }
}
```

### top_causal_factors.csv

CSV file with columns:
- `feature`: Feature name
- `causal_responsibility`: Causal responsibility score (0-1)
- `shap_importance`: Combined SHAP importance (0-1)
- `rank`: Rank by causal responsibility

## Integration with Risk Dashboard

The dashboard outputs are designed to be consumed by the risk dashboard:

1. **Load dashboard_data.json** for complete data structure
2. **Use top_causal_factors.csv** for causal factor visualization
3. **Use combined_shap_importance.csv** for feature importance plots

### Dashboard Integration Example

```python
import json
import pandas as pd
from pathlib import Path

# Load dashboard data
dashboard_path = Path("outputs/shap_ffa/Combined/dashboard_data.json")
with open(dashboard_path) as f:
    dashboard_data = json.load(f)

# Get top causal factors
top_factors = dashboard_data['top_causal_factors']
for factor in top_factors:
    print(f"{factor['feature']}: {factor['causal_responsibility']:.4f}")
```

## Advanced: Using Actual SHAP Values

The workflow automatically computes actual SHAP values from trained models:

1. **Train models in Python**: Use `train_python_models.py` to train and save models
2. **SHAP computation**: The workflow automatically loads models and computes SHAP values
3. **Combine with FFA**: SHAP values are automatically integrated with FFA analysis

## Notes

- **Aggregated Feature Importance**: The workflow uses aggregated feature importance from calculator models (mean importance across MC-CV splits) as the basis for SHAP value computation and FFA analysis. This provides robust feature rankings for clinical features (eGFR, bilirubin, albumin, cardiac support, etc.).

- **Clinical Features**: The PHTS calculator models use clinical features (not ICD/CPT/drug codes):
  - Kidney function: eGFR, creatinine, dialysis history
  - Liver function: bilirubin, ALT, AST
  - Nutrition: albumin, pre-albumin, BMI
  - Cardiac support: VAD, ECMO
  - Respiratory: ventilation, tracheostomy
  - Demographics: age, CHD subtypes
  - PRA: panel reactive antibodies

- **Weight Tuning**: Adjust `--weight-catboost` and `--weight-xgboost` based on model performance. CatBoost typically performs best, so default weight is 0.6.

- **Top K Selection**: The `--top-k` parameter controls how many causal factors are extracted. Use 10 for dashboard visualization, but you can extract more for detailed analysis.

## Future Enhancements

1. **Direct SHAP Computation**: Integrate actual SHAP value computation for survival models
2. **Full FFA Integration**: Complete integration with `run_full_ffa_analysis.py`
3. **Interactive Dashboard**: Generate interactive visualizations
4. **Model Comparison**: Compare causal factors across cohorts

## Troubleshooting

### No Models Found

Ensure `train_python_models.py` has completed successfully and generated model files in `outputs/models/{cohort}/`.

### Missing Features

If features don't align between CatBoost and XGBoost, the workflow will use available features from both models.

### Low Causal Scores

If causal responsibility scores are very low, check:
1. Feature importance values in source files
2. Weight distribution between models
3. Feature normalization
