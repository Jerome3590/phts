# Local Testing Guide

## Overview

The `test_local.py` script allows you to test the PHTS Lambda function locally without deploying to AWS. It simulates API Gateway events and runs the Lambda handler directly.

## Prerequisites

1. **Prepare Lambda Directory**: Run `prepare_lambda_dir_phts.py` to create `lambda_dir_phts/` with models and data
2. **Install Dependencies**: Ensure all Python dependencies are installed (numpy, pandas, catboost, xgboost, boto3)

## Running Tests

```bash
cd graft-loss/cohort_analysis/calculator/risk_dashboard
python test_local.py
```

## What It Tests

The script tests all API Gateway endpoints:

1. **GET /metadata** - Returns available cohorts and API information
2. **POST /risk (Baseline)** - Calculates risk using baseline model
3. **POST /risk (Enhanced)** - Calculates risk using enhanced model
4. **POST /causal (Baseline)** - Returns causal factors for baseline model
5. **POST /causal (Enhanced)** - Returns causal factors for enhanced model
6. **Model Comparison** - Compares baseline vs enhanced model predictions

## Expected Results

### Success Case

If `lambda_dir_phts/` is properly prepared with models in `Combined_base/` and `Combined_enhanced/` directories:

```
[PASS]: Metadata (GET)
[PASS]: Risk Baseline (POST)
[PASS]: Risk Enhanced (POST)
[PASS]: Causal Baseline (POST)
[PASS]: Causal Enhanced (POST)
[PASS]: Model Comparison

Total: 6/6 tests passed
```

### Partial Success (Current State)

The `/metadata` endpoint should always work as it doesn't require models:

```
[PASS]: Metadata (GET)
[FAIL]: Risk Baseline (POST) - Models not found
[FAIL]: Risk Enhanced (POST) - Models not found
[FAIL]: Causal Baseline (POST) - Dashboard data not found
[FAIL]: Causal Enhanced (POST) - Dashboard data not found
[FAIL]: Model Comparison - Models not found
```

This is expected if:
- Models haven't been prepared yet
- Models are in `Combined/` instead of `Combined_base/` and `Combined_enhanced/`
- Dashboard data hasn't been generated for baseline/enhanced variants

## Directory Structure Required

For full testing, `lambda_dir_phts/` should have:

```
lambda_dir_phts/
├── models/
│   ├── Combined_base/
│   │   ├── catboost_model.cbm
│   │   ├── xgboost_model.ubj
│   │   ├── xgboost_rf_model.ubj
│   │   └── best_model.txt
│   └── Combined_enhanced/
│       ├── catboost_model.cbm
│       ├── xgboost_model.ubj
│       ├── xgboost_rf_model.ubj
│       └── best_model.txt
├── dashboard_data/
│   ├── Combined_base/
│   │   └── dashboard_data.json
│   └── Combined_enhanced/
│       └── dashboard_data.json
├── model_features/
│   ├── Combined_base/
│   │   └── feature_metadata.json
│   └── Combined_enhanced/
│       └── feature_metadata.json
└── risk_distributions/
    └── risk_distributions.json
```

## What the Test Validates

1. **API Gateway Event Format**: Simulates correct API Gateway proxy integration events
2. **Endpoint Routing**: Tests that the Lambda handler correctly routes to `/metadata`, `/risk`, and `/causal`
3. **Model Variant Support**: Verifies that `model_variant=base` and `model_variant=enhanced` work correctly
4. **Response Format**: Checks that responses match expected API Gateway format with CORS headers
5. **Error Handling**: Tests error responses when models/data are missing

## Troubleshooting

### Models Not Found

If you see "Model not found" errors:

1. Check that `lambda_dir_phts/models/` exists
2. Verify `Combined_base/` and `Combined_enhanced/` directories exist
3. Ensure model files (`.cbm`, `.ubj`) are present
4. Run `prepare_lambda_dir_phts.py` to prepare the directory structure

### Dashboard Data Not Found

If you see "Dashboard data not found" errors:

1. Check that `lambda_dir_phts/dashboard_data/` exists
2. Verify `Combined_base/` and `Combined_enhanced/` subdirectories exist
3. Ensure `dashboard_data.json` files are present
4. Run SHAP/FFA analysis to generate dashboard data for both model variants

### S3 Errors (Expected Locally)

If you see S3 404 errors, this is expected when testing locally. The Lambda function:
1. First tries to load from local filesystem (`lambda_dir_phts/`)
2. Falls back to S3 if local files aren't found

For local testing, ensure all files are in `lambda_dir_phts/` so S3 fallback isn't needed.

## Next Steps

After local testing passes:

1. Build Docker image: `./docker_build_phts.sh`
2. Push to ECR and update Lambda
3. Test via actual API Gateway: `curl https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata?cohort=Combined`
