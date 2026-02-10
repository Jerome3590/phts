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

The script tests API Gateway endpoints:

1. **GET /metadata** - Returns available cohorts and API information
2. **POST /risk** - Calculates risk using the top-features model (Combined_top)
3. **POST /causal** - Returns causal factors for the top-features model

## Expected Results

### Success Case

If `lambda_dir_phts/` is prepared with `Combined_top/` (run `prepare_lambda_dir_phts.py` after training with `--top_features_only` and running SHAP/FFA for top):

```
[PASS]: Metadata (GET)
[PASS]: Risk (POST) - Combined_top
[PASS]: Causal (POST) - Combined_top

Total: 3/3 tests passed
```

### Partial Success (Current State)

The `/metadata` endpoint should always work as it doesn't require models:

```
[PASS]: Metadata (GET)
[FAIL]: Risk (POST) - Models not found
[FAIL]: Causal (POST) - Dashboard data not found
```

This is expected if:
- `prepare_lambda_dir_phts.py` has not been run after training with `--top_features_only`
- `Combined_top/` is missing under `outputs/models/` or `outputs/shap_ffa/`

## Directory Structure Required

For full testing, `lambda_dir_phts/` should have:

```
lambda_dir_phts/
├── models/
│   └── Combined_top/
│       ├── catboost_model.cbm (or xgboost*.ubj per best_model.txt)
│       └── best_model.txt
├── dashboard_data/
│   └── Combined_top/
│       └── dashboard_data.json
├── model_features/
│   └── Combined_top/
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

1. Check that `lambda_dir_phts/models/Combined_top/` exists
2. Ensure model files (e.g. `.cbm` or `.ubj` per best_model.txt) and `best_model.txt` are present
3. Run `prepare_lambda_dir_phts.py` after training with `--top_features_only` and SHAP/FFA for top

### Dashboard Data Not Found

1. Check that `lambda_dir_phts/dashboard_data/Combined_top/dashboard_data.json` exists
2. Run SHAP/FFA with `--model-variant top` to generate dashboard data, then re-run `prepare_lambda_dir_phts.py`

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
