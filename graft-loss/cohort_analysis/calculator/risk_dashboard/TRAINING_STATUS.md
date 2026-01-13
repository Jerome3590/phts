# Training Status - All Cohorts

## ✅ Completed Training

### CHD Cohort
- **Models Trained**: ✅
  - CatBoost: C-index 0.391
  - XGBoost: C-index 0.645 (Best)
  - XGBoost RF: C-index 0.614
- **Dashboard Data**: ✅ Generated (using feature importance)
- **Location**: `outputs/models/CHD/` and `outputs/shap_ffa/CHD/`

### Combined Cohort
- **Models Trained**: ✅ (Previously completed)
- **Dashboard Data**: ✅ Generated
- **Location**: `outputs/models/Combined/` and `outputs/shap_ffa/Combined/`

### Myocardio Cohort
- **Models Trained**: ✅
  - CatBoost: C-index 0.599 (Best)
  - XGBoost: C-index 0.507
  - XGBoost RF: C-index 0.545
- **Dashboard Data**: ⚠️ Partial (SHAP/FFA workflow had import errors, but models are trained)
- **Location**: `outputs/models/Myocardio/`

## Current Status

### Lambda Directory
- **All 3 cohorts have models** in `lambda_dir_phts/models/`
- **CHD and Combined have dashboard data** in `lambda_dir_phts/dashboard_data/`
- **Myocardio dashboard data is missing** (but Lambda will handle gracefully)

### Next Steps

1. **Fix SHAP import issues** in `shap_analysis/run_shap_analysis.py`:
   - Remove `age_band_to_fname` import (not needed for diagnostic cohorts)
   - Fix `get_xgb_cpu_nthread` import or make it optional

2. **Complete Myocardio SHAP/FFA**:
   ```bash
   python run_shap_ffa_workflow.py --cohort Myocardio --top-k 10
   ```

3. **Rebuild Docker image** (when Docker Desktop is working):
   ```bash
   cd risk_dashboard
   ./docker_build_phts.sh
   ```

4. **Update Lambda function**:
   ```bash
   aws lambda update-function-code \
     --function-name phts-risk-calculator \
     --image-uri 535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest
   ```

## Lambda Function Behavior

The Lambda function has been updated to handle missing dashboard data gracefully:
- Returns empty causal factors with a warning for cohorts without dashboard data
- Risk calculation will still work if models exist (even without dashboard data)
- The `/metadata` endpoint shows which cohorts have data

## Model Performance Summary

| Cohort | Best Model | C-index | Model Type |
|--------|------------|---------|------------|
| CHD | XGBoost | 0.645 | Gradient Boosting |
| Combined | (from previous training) | - | - |
| Myocardio | CatBoost | 0.599 | Gradient Boosting |
