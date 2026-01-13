# SHAP + FFA Integration for PHTS Calculator Models

This document describes the integrated SHAP and FFA analysis workflow for the PHTS (Pediatric Heart Transplant Survival) calculator models, including causal analysis.

## Overview

The workflow combines:
1. **SHAP Analysis**: Feature importance from CatBoost and XGBoost survival models using aggregated feature importance (mean across MC-CV splits)
2. **FFA Analysis**: Formal Feature Attribution using symbolic rule extraction from gradient-boosted models
3. **Causal Analysis**: Measure causal responsibility through counterfactual analysis and rule frequency
4. **Dashboard Outputs**: Top K causal factors for risk dashboard

## Causal Analysis Summary

### What is Causal Analysis?

Causal analysis identifies which clinical features have **causal responsibility** for graft loss risk, not just correlation. It combines:

1. **Rule-Based Analysis**: Extracts symbolic rules from trained models (XGBoost JSON)
2. **SHAP Importance**: Uses SHAP values to filter and prioritize rules
3. **Causal Responsibility**: Calculates how much each feature contributes causally to the outcome

### Causal Responsibility Calculation

For each feature, causal responsibility is computed as:

```
causal_responsibility = (rule_frequency / total_rules) × SHAP_importance
```

Where:
- **rule_frequency**: Number of rules containing the feature
- **total_rules**: Total number of extracted rules
- **SHAP_importance**: Combined SHAP importance from CatBoost and XGBoost

### Why Causal Analysis Matters

- **Clinical Interpretability**: Identifies which features clinicians can actually modify to affect outcomes
- **Intervention Guidance**: Shows which interventions might reduce graft loss risk
- **Feature Prioritization**: Ranks features by causal impact, not just correlation
- **Model Transparency**: Provides explainable AI for clinical decision-making

## Cohorts

The PHTS calculator uses **diagnostic cohorts** (not age bands):
- **CHD**: Congenital Heart Disease cohort
- **Combined**: All primary diagnoses (includes `primary_etiology` as feature)
- **Myocardio**: Cardiomyopathy and Myocarditis cohort

## Clinical Features

The PHTS calculator models use **clinical features** (not ICD/CPT/drug codes from previous projects). These are modifiable features that can be influenced by clinical intervention:

### Kidney Function
- `egfr_tx`, `egfr_listing` - Estimated GFR at transplant/listing (mL/min/1.73m²)
- `egfr_tx_cat`, `egfr_listing_cat` - eGFR categories (severe/moderate/mild/normal)
- `hxdysdia_bin` - History of dialysis (binary)
- `egfr_change` - Change in eGFR from listing to transplant
- `txbun_r` - BUN at transplant (mg/dL)
- `txcreat_r` - Creatinine at transplant (mg/dL)

### Liver Function
- `txbili_t_r` - Total bilirubin at transplant (mg/dL)
- `txbili_t_r_high` - High bilirubin indicator (>1.5, binary)
- `txalt`, `txalt_high` - ALT at transplant (U/L, high >90)
- `txast` - AST at transplant (U/L)

### Nutrition
- `txpalb_r` - Pre-albumin at transplant (mg/dL)
- `txsa_r`, `txsa_r_low` - Serum albumin at transplant (g/dL, low <3)
- `txtp_r` - Total protein at transplant (g/dL)
- `bmi_txpl` - BMI at transplant

### Cardiac Support
- `txvad` - VAD at transplant (binary)
- `txecmo`, `slecmo`, `ecmo_combined` - ECMO indicators (binary)
- `txnomcsd` - Mechanical Circulatory Support Device (binary)

### Respiratory
- `txvent` - Ventilation at transplant (binary)
- `hxtrach`, `ltxtrach` - Tracheostomy indicators (binary)

### Demographics
- `age_listing`, `age_txpl` - Age at listing/transplant (years)
- `chd_hlh`, `chd_*` - CHD subtypes (CHD cohort only)

### PRA (Panel Reactive Antibodies)
- `lsfcpra`, `lsfprab`, `lsfprat` - PRA at listing (%)
- `txfcpra` - PRA at transplant (%)

### Diagnosis
- `primary_etiology` - Primary diagnosis (Combined cohort only)
  - Values: "Congenital Heart Disease", "Cardiomyopathy", "Myocarditis", etc.

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

### Workflow Steps (Internal)

The `run_shap_ffa_workflow.py` script performs the following steps:

1. **Load Models**: Loads best model (from `best_model.txt`) and all model variants
2. **Load Feature Importance**: Loads aggregated feature importance from calculator model outputs
   - Path: `outputs/models/{cohort}/importance_{cohort}_{model}.csv`
   - Format: CSV with `feature` and `importance` columns
   - Aggregation: Mean importance across 25 MC-CV splits
3. **Compute SHAP Values**: Generates SHAP values from trained models
   - Uses CatBoost and XGBoost models
   - Combines SHAP importance with weights (default: 0.6 CatBoost, 0.4 XGBoost)
4. **Extract Rules**: Extracts symbolic rules from XGBoost model JSON
   - Loads XGBoost JSON from `final_model_json/` directory
   - Converts tree structures to Boolean logic formulas
   - Filters rules using SHAP importance
5. **Calculate Causal Responsibility**: Computes causal responsibility for each feature
   - Combines rule frequency with SHAP importance
   - Formula: `causal_responsibility = (rule_count / total_rules) × SHAP_importance`
6. **Generate Dashboard Outputs**: Creates files for risk dashboard
   - `dashboard_data.json` - Complete data structure
   - `top_causal_factors.csv` - Top K causal factors
   - `ffa_causal_factors.csv` - Full FFA causal analysis results

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

## Feature Importance Source

Feature importance is loaded from calculator model outputs:
- **Path**: `outputs/models/{cohort}/importance_{cohort}_{model}.csv`
- **Format**: CSV with columns `feature` and `importance`
- **Aggregation**: Mean importance across 25 MC-CV splits
- **Models**: CatBoost, XGBoost, XGBoost RF (all three models)

This aggregated importance provides robust feature rankings for clinical features and is used as the basis for SHAP value computation and FFA analysis.

## Interaction Analysis

The FFA framework includes **multi-feature interaction analysis** to identify clinical feature combinations that affect graft loss risk:

### Feature Interactions

- **Pairs**: Tests combinations of 2 features
  - Example: `egfr_tx_cat|txbili_t_r_high` (kidney + liver function)
  - Measures synergy/antagonism between feature pairs
  
- **Triplets**: Tests combinations of 3 features
  - Example: `txecmo|egfr_tx_cat|txsa_r_low` (cardiac support + kidney + nutrition)
  - Identifies complex multi-factor interactions

### Interaction Effects

- **Synergy**: Positive interaction effect (features together increase risk more than sum of individual effects)
- **Antagonism**: Negative interaction effect (features together increase risk less than sum of individual effects)

### Output

Interaction analysis results are saved to:
- `outputs/shap_ffa/{cohort}/interaction_analysis.parquet`
- Contains feature pairs/triplets with interaction effects

## Notes

- **Model Selection**: The workflow checks `best_model.txt` to determine which model to use for rule extraction. XGBoost models are preferred for rule extraction (CatBoost JSON is harder to parse due to categorical hashing).

- **Weight Tuning**: Adjust `--weight-catboost` and `--weight-xgboost` based on model performance. CatBoost typically performs best, so default weight is 0.6.

- **Top K Selection**: The `--top-k` parameter controls how many causal factors are extracted. Use 10-20 for dashboard visualization, but you can extract more for detailed analysis.

- **Rule Extraction**: Only XGBoost models are used for rule extraction. CatBoost models are used for SHAP importance but not for FFA rule extraction due to complex categorical handling.

## Causal Analysis Workflow

### Complete Workflow Diagram

```
1. Train Calculator Models
   ↓
2. Generate Model JSONs (XGBoost)
   ↓
3. Load Aggregated Feature Importance (from MC-CV)
   ↓
4. Compute SHAP Values (CatBoost + XGBoost)
   ↓
5. Extract Rules from XGBoost JSON
   ↓
6. Filter Rules using SHAP Importance
   ↓
7. Calculate Causal Responsibility
   (rule_frequency × SHAP_importance)
   ↓
8. Generate Dashboard Outputs
   (dashboard_data.json, top_causal_factors.csv)
```

### Key Components

1. **Rule Extraction** (`ffa_analysis/xgboost_axp_explainer.py`):
   - Parses XGBoost JSON model structure
   - Converts tree nodes to Boolean logic formulas
   - Creates rule clauses for each feature condition

2. **SHAP Integration** (`run_shap_ffa_workflow.py`):
   - Computes SHAP values from trained models
   - Combines CatBoost and XGBoost SHAP importance
   - Uses SHAP to filter and prioritize rules

3. **Causal Calculation** (`run_shap_ffa_workflow.py`):
   - Counts rule frequency for each feature
   - Multiplies by SHAP importance
   - Ranks features by causal responsibility

4. **Dashboard Generation** (`run_shap_ffa_workflow.py`):
   - Creates `dashboard_data.json` with complete structure
   - Generates `top_causal_factors.csv` for visualization
   - Includes summary statistics

## Future Enhancements

1. **Direct SHAP Computation**: Integrate actual SHAP value computation for survival models
2. **CatBoost Rule Extraction**: Develop method to extract rules from CatBoost models
3. **Interactive Dashboard**: Generate interactive visualizations
4. **Model Comparison**: Compare causal factors across cohorts
5. **Interaction Visualization**: Visualize feature interaction effects

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
