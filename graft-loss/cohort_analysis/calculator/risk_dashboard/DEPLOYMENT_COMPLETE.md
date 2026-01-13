# PHTS Dashboard Deployment - Complete ✅

## Deployment Summary

All three cohorts have been successfully trained, analyzed, and deployed!

### ✅ Completed Steps

1. **All Cohorts Trained**:
   - CHD: XGBoost (C-index: 0.645) - Best
   - Combined: Previously trained
   - Myocardio: CatBoost (C-index: 0.599) - Best

2. **SHAP/FFA Analysis Complete**:
   - CHD: Dashboard data generated
   - Combined: Dashboard data generated
   - Myocardio: Dashboard data generated

3. **SHAP Import Issues Fixed**:
   - Added `prim_dx_fname()` for diagnostic cohorts
   - Made `get_xgb_cpu_nthread` and `is_linux` imports optional
   - Updated terminology from age_band to prim_dx

4. **Lambda Directory Prepared**:
   - 9 model files (3 cohorts × 3 models each)
   - 3 dashboard data files (one per cohort)

5. **Docker Image Rebuilt**:
   - Includes all three cohorts
   - Docker format (Lambda compatible)

6. **Lambda Function Updated**:
   - Active and ready
   - All three cohorts available

## Deployment URLs

- **Dashboard**: `https://jerome-dixon.io/uva/phts-risk-calculator/`
- **API Gateway**: `https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod`
- **Lambda Function**: `phts-risk-calculator` (us-east-1)

## API Endpoints

### GET /metadata
Returns available cohorts and causal factors:
```bash
# All cohorts
curl "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata"

# Specific cohort
curl "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata?cohort=CHD"
```

### POST /risk
Calculate risk score:
```bash
curl -X POST "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/risk" \
  -H "Content-Type: application/json" \
  -d '{
    "cohort": "CHD",
    "features": {
      "egfr_tx": 60.0,
      "txbun_r": 20.0,
      "ltxtrach": 1
    }
  }'
```

### POST /causal
Get causal factors:
```bash
curl -X POST "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/causal" \
  -H "Content-Type: application/json" \
  -d '{
    "cohort": "CHD",
    "top_k": 10
  }'
```

## Available Cohorts

1. **CHD** (Congenital Heart Disease)
   - Best Model: XGBoost
   - C-index: 0.645
   - Top Features: ltxtrach, txbun_r, neuroth

2. **Combined** (All Primary Diagnoses)
   - Previously trained
   - Top Features: ltxtrach, txnomcsd, chd_papvr

3. **Myocardio** (Cardiomyopathy/Myocarditis)
   - Best Model: CatBoost
   - C-index: 0.599
   - Top Features: prim_dx, txicu, lldl_r

## Model Files Deployed

Each cohort includes:
- `catboost_model.cbm` - CatBoost binary
- `xgboost_model.ubj` - XGBoost binary
- `xgboost_rf_model.ubj` - XGBoost RF binary
- `best_model.txt` - Best model selection
- `final_model_json/` - XGBoost JSON for FFA

## Dashboard Data Deployed

Each cohort includes:
- `dashboard_data.json` - Complete dashboard data with causal factors
- `top_causal_factors.csv` - Top K causal factors

## Next Steps

1. **Test Dashboard**: Open `https://jerome-dixon.io/uva/phts-risk-calculator/` in browser
2. **Test All Cohorts**: Verify CHD, Combined, and Myocardio all work
3. **Monitor Lambda Logs**: Check for any errors
   ```bash
   aws logs tail /aws/lambda/phts-risk-calculator --follow
   ```

## Troubleshooting

If you encounter issues:

1. **Check Lambda Status**:
   ```bash
   aws lambda get-function --function-name phts-risk-calculator --region us-east-1
   ```

2. **Check API Gateway**:
   ```bash
   aws apigateway get-rest-apis --query "items[?name=='phts-calculator-api']"
   ```

3. **View Lambda Logs**:
   ```bash
   aws logs tail /aws/lambda/phts-risk-calculator --follow
   ```

## Files Modified

- `shap_analysis/run_shap_analysis.py` - Fixed imports, added prim_dx_fname
- `phts_lambda_function.py` - Handles missing cohorts gracefully
- `docker_build_phts.sh` - Uses Docker format for Lambda compatibility

---

**Deployment Date**: $(date)
**Status**: ✅ Complete - All 3 Cohorts Deployed
