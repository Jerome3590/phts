# PHTS Risk Calculator - Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the PHTS Risk Calculator Dashboard to AWS, including lessons learned from production deployment.

## Architecture Components

- **Frontend**: Static HTML/JavaScript hosted on S3
- **Backend**: AWS Lambda function (container-based)
- **API**: API Gateway REST API
- **Storage**: ECR (Docker images), S3 (models/data fallback)
- **Models**: Baked into Lambda container for fast access

## Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **Docker** installed and running
3. **Top-features models trained** (one per cohort): `python train_python_models.py --cohort CHD --top_features_only` (repeat for Myocardio, Combined) → `calculator/outputs/models/{cohort}_top/`
4. **Dashboard data + FFA + Reverse FI** generated per cohort (see **End-to-end** below): `outputs/shap_ffa/{cohort}_top/` includes `dashboard_data.json`, causal factors, and Reverse Feature Importance (`missed_predictions_drivers.json`, `missed_predictions_feature_profile.csv`).
5. **Risk distributions computed** in `calculator/outputs/risk_distributions/`

### Docker Setup

If you get a "permission denied" error when building Docker images, add your user to the docker group:

```bash
# Add your user to docker group
sudo usermod -aG docker $USER

# Apply the group changes (choose one):
# Option 1: Log out and log back in (recommended)
# Option 2: Run this command in your current session:
newgrp docker

# Verify it worked:
groups | grep docker
docker ps
```

**Note:** After adding your user to the docker group, you must log out and back in (or run `newgrp docker`) for the changes to take effect.

## Quick Start

For experienced users, here's the fastest path to deployment:

```bash
cd graft-loss/cohort_analysis/calculator/risk_dashboard

# 1. Prepare models and data
python prepare_lambda_dir_phts.py

# 2. Build and push Docker image
./docker_build_phts.sh

# 3. Update Lambda (get ECR URI from step 2 output)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest"
aws lambda update-function-code \
    --function-name phts-risk-calculator \
    --image-uri ${ECR_URI} \
    --region us-east-1

# 4. Set up API Gateway
./setup_api_gateway.sh

# 5. Upload HTML to S3
aws s3 cp phts_dashboard.html \
    s3://jerome-dixon.io/uva/phts-risk-calculator/index.html \
    --content-type "text/html" \
    --cache-control "no-cache" \
    --region us-east-1
aws s3 cp phts_readme.html \
    s3://jerome-dixon.io/uva/phts-risk-calculator/phts_readme.html \
    --content-type "text/html" \
    --cache-control "no-cache" \
    --region us-east-1
```

**Documentation tab:** The Documentation button opens `phts_readme.html`. You must upload `phts_readme.html` to the same S3 prefix as the dashboard (e.g. `uva/phts-risk-calculator/phts_readme.html`) or the Documentation tab will 404 or show an old version. After updating the doc, re-upload it:
```bash
aws s3 cp phts_readme.html s3://YOUR_BUCKET/YOUR_PREFIX/phts_readme.html --content-type "text/html" --region us-east-1
```

**Verification:**
```bash
# Test API
curl "https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/prod/metadata?cohort=Combined"
```

## End-to-end: FFA + Reverse FI + Lambda deployment

After models are trained, a single flow runs **SHAP + FFA + Reverse Feature Importance**, prepares the Lambda directory (including Reverse FI artifacts), and deploys Lambda + API + S3:

```bash
cd graft-loss/cohort_analysis/calculator

# Full E2E (set deployed variant → run FFA+Reverse FI → prepare Lambda dir → deploy)
./run_e2e_ffa_lambda_deploy.sh

# Or Python (cross-platform; step 4 still needs bash on Windows for deploy_complete.sh)
python run_e2e_ffa_lambda_deploy.py
```

**Options:**
- `--no-deploy` — Stop after `prepare_lambda_dir_phts.py` (no Docker/Lambda/S3). Then run `cd risk_dashboard && ./deploy_complete.sh` when ready.
- `--no-ffa` — Skip SHAP/FFA+Reverse FI; use existing `outputs/shap_ffa/` (e.g. after re-training only).

**Steps performed:**
1. **Set deployed variant** — `compare_top_vs_wisotzkey.py --set-deployed` (best of top vs Wisotzkey per cohort).
2. **SHAP + FFA + Reverse FI** — `run_shap_ffa_reverse_fi_s3.py --no-upload` (writes to `outputs/shap_ffa/{cohort}_top/`, including `missed_predictions_drivers.json`, `missed_predictions_feature_profile.csv`).
3. **Prepare Lambda directory** — `prepare_lambda_dir_phts.py` (copies models, dashboard_data, Reverse FI artifacts into `risk_dashboard/lambda_dir_phts/`).
4. **Deploy** — `risk_dashboard/deploy_complete.sh` (Docker build → push ECR → update Lambda → API Gateway → inject API URL → upload HTML to S3).

The Lambda container and dashboard therefore include **FFA causal factors and Reverse Feature Importance** artifacts; the API/dashboard can be extended later to expose them.

## Deployment Workflow

### Step 1: Prepare Lambda Directory

Copy models, dashboard data, and risk distributions into Docker-ready structure:

```bash
cd graft-loss/cohort_analysis/calculator/risk_dashboard
python prepare_lambda_dir_phts.py
```

**What it creates:**
```
lambda_dir_phts/
├── models/
│   ├── CHD_top/, Myocardio_top/, Combined_top/ (and other variants)
│   │   (catboost_model.cbm, xgboost_model.ubj, best_model.txt, final_model_json/, ...)
│   └── {cohort}_deployed_variant.txt
├── model_features/
│   └── {variant}/ (feature_metadata.json)
├── dashboard_data/
│   └── {variant}/ (dashboard_data.json, top_causal_factors.csv,
│       missed_predictions_drivers.json, missed_predictions_feature_profile.csv/.parquet)
└── risk_distributions/
    └── risk_distributions.json
```

**Verification:**
- Check that all 3 cohorts have model files
- Verify dashboard_data.json exists for each cohort
- Confirm risk_distributions.json is present

---

### Step 2: Build and Push Docker Image

Build Docker image, push to ECR, and **update the Lambda function** so it uses the new image:

```bash
./docker_build_phts.sh
```

**What it does:**
1. Validates lambda directory structure
2. Builds Docker image (includes current `phts_lambda_function.py`)
3. Logs into ECR, creates repository if needed
4. Tags and pushes image to ECR
5. **Updates the Lambda function to use the new image** (so new code/endpoints take effect)

**Important:** After any change to Lambda code (e.g. new `/model-metrics` endpoint), you must rebuild and push; the script now runs `aws lambda update-function-code` by default so the deployed function picks up the new image. To skip the Lambda update (e.g. push only): `UPDATE_LAMBDA=false ./docker_build_phts.sh`.

**Output:** ECR image URI (e.g., `ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest`)

**Critical:** Use `DOCKER_BUILDKIT=0` to ensure Docker format (not OCI) for Lambda compatibility.

---

### Step 3: Create/Update Lambda Function

#### Create New Function

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest"

aws lambda create-function \
    --function-name phts-risk-calculator \
    --package-type Image \
    --code ImageUri=${ECR_URI} \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/phts-lambda-role \
    --timeout 60 \
    --memory-size 3008 \
    --environment Variables="{
        \"PHTS_BUCKET\":\"jerome-dixon.io\",
        \"S3_PREFIX\":\"uva/phts-risk-calculator\",
        \"RISK_DISTRIBUTION_PATH\":\"/var/task/risk_distributions\"
    }" \
    --region us-east-1
```

#### Update Existing Function

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest"

aws lambda update-function-code \
    --function-name phts-risk-calculator \
    --image-uri ${ECR_URI} \
    --region us-east-1
```

**Settings:**
- **Memory**: 3008 MB (for large models)
- **Timeout**: 60 seconds
- **Handler**: `phts_lambda_function.lambda_handler` (auto-detected for containers)

---

### Step 4: Set Up API Gateway

Create REST API and integrate with Lambda:

```bash
./setup_api_gateway.sh
```

**What it does:**
1. Creates REST API (or uses existing)
2. Creates resources: `/metadata`, `/model-metrics`, `/risk`, `/causal`
3. Creates methods: GET for `/metadata` and `/model-metrics`, POST for `/risk` and `/causal`
4. Configures Lambda proxy integration
5. Sets up CORS (OPTIONS methods)
6. Grants API Gateway permission to invoke Lambda
7. Deploys API to `prod` stage
8. **Automatically sets `API_GATEWAY_URL` in Lambda environment**

**Output:** API Gateway URL (e.g., `https://API_ID.execute-api.us-east-1.amazonaws.com/prod`)

**Known API ID:** `359vxflbzj` (if API Gateway already exists)

---

### Step 5: Update Lambda Environment Variables

Ensure Lambda has correct configuration:

```bash
API_GATEWAY_URL='https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod' \
  ./update_lambda_env.sh
```

**Environment Variables:**
- `API_GATEWAY_URL`: API Gateway endpoint (for metadata endpoint)
- `PHTS_BUCKET`: `jerome-dixon.io`
- `S3_PREFIX`: `uva/phts-risk-calculator`
- `RISK_DISTRIBUTION_PATH`: `/var/task/risk_distributions`

### Environment Variables Management

The Lambda function uses environment variables for configuration. These can be set during Lambda creation or updated later.

#### Required Variables

- **`API_GATEWAY_URL`**: The API Gateway endpoint URL
  - Format: `https://API_ID.execute-api.REGION.amazonaws.com/STAGE`
  - Used by: Lambda returns this in `/metadata` endpoint for frontend discovery
  - **Note**: Automatically set by `setup_api_gateway.sh`

- **`PHTS_BUCKET`**: S3 bucket name
  - Default: `jerome-dixon.io`
  - Used by: Lambda for S3 fallback (if models not in container)

- **`S3_PREFIX`**: S3 prefix path
  - Default: `uva/phts-risk-calculator`
  - Used by: Lambda for constructing S3 paths

#### Optional Variables

- **`MODEL_BASE_PATH`**: Path to models in container
  - Default: `/var/task/models`
  - Used by: Lambda to load models from container filesystem

- **`DASHBOARD_DATA_PATH`**: Path to dashboard data in container
  - Default: `/var/task/dashboard_data`
  - Used by: Lambda to load causal factors data

- **`RISK_DISTRIBUTION_PATH`**: Path to risk distributions in container
  - Default: `/var/task/risk_distributions`
  - Used by: Lambda for risk score normalization

- **`METRICS_S3_URL`**: Optional URL to the model metrics file in S3
  - Example: `https://bucket.s3.region.amazonaws.com/prefix/model_metrics.json`
  - Used by: Lambda `GET /model-metrics` response; the dashboard Documentation tab shows a "View in S3" link when set. Metrics are always read from `best_model.txt` in the container; this only adds a link to where the same (or full) metrics are stored in S3.

#### Setting Environment Variables

**Method 1: Using update_lambda_env.sh (Recommended)**

```bash
API_GATEWAY_URL='https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod' \
  ./update_lambda_env.sh
```

**Method 2: Using AWS CLI Directly**

```bash
aws lambda update-function-configuration \
    --function-name phts-risk-calculator \
    --environment Variables="{
        \"API_GATEWAY_URL\":\"https://API_ID.execute-api.REGION.amazonaws.com/prod\",
        \"PHTS_BUCKET\":\"jerome-dixon.io\",
        \"S3_PREFIX\":\"uva/phts-risk-calculator\",
        \"RISK_DISTRIBUTION_PATH\":\"/var/task/risk_distributions\"
    }" \
    --region us-east-1
```

**Method 3: View Current Variables**

```bash
aws lambda get-function-configuration \
    --function-name phts-risk-calculator \
    --query 'Environment.Variables' \
    --output json | jq '.'
```

#### Dynamic API URL Discovery

The HTML page can discover the API URL dynamically:
1. **From Lambda Metadata Endpoint**: HTML calls `/metadata`, Lambda returns `api_url`
2. **From Window Variable**: Deployment script injects `window.LAMBDA_API_URL`

---

### Step 6: Upload HTML to S3

Deploy frontend to S3:

```bash
aws s3 cp phts_dashboard.html \
    s3://jerome-dixon.io/uva/phts-risk-calculator/index.html \
    --content-type "text/html" \
    --cache-control "no-cache" \
    --region us-east-1
```

**Note:** Use `--cache-control "no-cache"` to prevent browser caching during development.

---

## Complete Automated Deployment

```bash
#!/bin/bash
# Complete deployment script

set -e

echo "=== PHTS Dashboard Deployment ==="

# Step 1: Prepare
echo "Step 1: Preparing models and data..."
python prepare_lambda_dir_phts.py

# Step 2: Build Docker
echo "Step 2: Building and pushing Docker image..."
./docker_build_phts.sh
ECR_URI=$(aws ecr describe-repositories \
    --repository-names phts-risk-calculator \
    --query 'repositories[0].repositoryUri' \
    --output text):latest

# Step 3: Update Lambda
echo "Step 3: Updating Lambda function..."
aws lambda update-function-code \
    --function-name phts-risk-calculator \
    --image-uri ${ECR_URI} \
    --region us-east-1
aws lambda wait function-updated \
    --function-name phts-risk-calculator \
    --region us-east-1

# Step 4: API Gateway
echo "Step 4: Setting up API Gateway..."
./setup_api_gateway.sh

# Step 5: Upload HTML
echo "Step 5: Uploading HTML to S3..."
aws s3 cp phts_dashboard.html \
    s3://jerome-dixon.io/uva/phts-risk-calculator/index.html \
    --content-type "text/html" \
    --cache-control "no-cache" \
    --region us-east-1

echo "=== Deployment Complete ==="
```

---

## Lessons Learned

### 1. Docker Image Format

**Issue:** Lambda requires Docker format, not OCI format.

**Solution:**
```bash
DOCKER_BUILDKIT=0 docker build -f Dockerfile.phts -t phts-risk-calculator:latest .
```

**Why:** Lambda container images must be in Docker format. BuildKit defaults to OCI format, which causes `InvalidImage` errors.

---

### 2. CatBoost/XGBoost Logging Conflicts

**Issue:** "Only one of parameters ['verbose', 'logging_level', 'verbose_eval', 'silent'] should be set"

**Solution:**
- **XGBoost**: Set `os.environ['XGBOOST_VERBOSE'] = '0'` globally before any XGBoost operations
- **CatBoost**: Use `verbose=False, logging_level='Silent'` when initializing, and `verbose=False` when calling `predict()`

**Why:** Models saved with conflicting verbose parameters cause errors during prediction.

---

### 3. API Gateway to Lambda Permissions

**Issue:** API Gateway not invoking Lambda (403/500 errors).

**Solution:**
```bash
aws lambda add-permission \
    --function-name phts-risk-calculator \
    --statement-id apigateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:REGION:ACCOUNT:API_ID/*/*"
```

**Why:** API Gateway needs explicit permission to invoke Lambda, even if Lambda has API Gateway trigger.

---

### 4. Path Extraction in Lambda Handler

**Issue:** Empty `path` and `resource` fields in API Gateway events.

**Solution:** Check multiple event fields:
```python
path = event.get("path") or \
       event.get("resource") or \
       event.get("requestContext", {}).get("path") or \
       event.get("requestContext", {}).get("resourcePath")
```

**Why:** API Gateway event structure varies. Always check multiple fields and provide fallbacks.

---

### 5. CORS Configuration

**Issue:** CORS errors from browser.

**Solution:**
- Lambda returns CORS headers in all responses
- API Gateway OPTIONS methods configured
- Frontend uses `mode: 'cors'` in fetch requests

**Headers Required:**
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET,POST,OPTIONS
Access-Control-Allow-Headers: Content-Type,Authorization
Access-Control-Max-Age: 3600
```

**If "Calculate Risk" shows "Unable to connect" from the live website:** The browser sends an OPTIONS preflight before POST /risk. If OPTIONS returns 500 or no CORS headers, the browser blocks the request. Re-run the API Gateway setup so OPTIONS is routed to Lambda (Lambda returns 200 with CORS): `.\setup_api_gateway.ps1` or `./setup_api_gateway.sh`, then redeploy the API.

---

### 6. Browser Caching

**Issue:** HTML updates not visible due to browser caching.

**Solution:**
- Add cache-control meta tags to HTML
- Use `--cache-control "no-cache"` when uploading to S3
- Add version parameter to API calls: `?v=${Date.now()}`

---

### 7. Model Loading Strategy

**Best Practice:** Two-tier loading:
1. **Container filesystem** (primary): Models baked into image at `/var/task/models/`
2. **S3 fallback**: If not found in container, load from S3

**Why:** Fast access from container, flexibility to update without rebuild.

---

### 8. Risk Distribution Computation

**Issue:** CatBoost verbose conflict when computing distributions.

**Solution:** Use Pool for prediction (matches training):
```python
pool = Pool(data=X, cat_features=cat_features)
predictions = model.predict(pool)
```

**Note:** Myocardio cohort may use placeholder distribution if CatBoost model has conflicting parameters.

---

### 9. Feature Handling

**Critical:** Always handle both numeric and categorical features:
- **CatBoost**: Use DataFrame with categoricals as objects/strings
- **XGBoost**: Convert categoricals to numeric codes
- **Check actual unique values**, not just factor levels (MC-CV splits can cause constant columns)

---

### 10. Lambda Initialization

**Issue:** No CloudWatch logs created (function failing during initialization).

**Solution:**
- Wrap S3 client initialization in try/except
- Add logging at start of handler
- Ensure all imports are wrapped in try/except

---

## Troubleshooting

### Lambda Function Not Updating

```bash
# Check Lambda status
aws lambda get-function \
    --function-name phts-risk-calculator \
    --query 'Configuration.[State,LastUpdateStatus]'

# Check CloudWatch logs
aws logs tail /aws/lambda/phts-risk-calculator --follow
```

### API Gateway Not Working

```bash
# Test API directly
curl -X POST 'https://API_ID.execute-api.REGION.amazonaws.com/prod/risk' \
  -H 'Content-Type: application/json' \
  -d '{"cohort":"Combined","features":{"egfr_tx":60.0}}'
```

### Documentation tab: "Failed to load metrics"

The Documentation tab fetches metrics from **GET /model-metrics**. If that route is missing in API Gateway, you may see 403 "Missing Authentication Token" or "Failed to fetch".

**Fix:** Add the `/model-metrics` route and redeploy:

1. Re-run the API Gateway setup. The script is idempotent: it gets-or-creates each resource, so you can safely run it even if `/metadata`, `/risk`, `/causal` already exist. It will add `/model-metrics` if missing:
   ```bash
   ./setup_api_gateway.sh
   ```
   The script creates the `model-metrics` resource, GET method, Lambda integration, and deploys the API.

2. Verify: `curl -s 'https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/prod/model-metrics'` should return JSON with `best_model`, `c_index`, etc. (or nulls if `best_model.txt` is not in the container).

**If the route works but returns 404 from Lambda:** The Lambda container image may not have been updated. Rebuild and push the image, then update the function code so Lambda uses the new image: `./docker_build_phts.sh` (it now runs `update-function-code` by default), or manually: `aws lambda update-function-code --function-name phts-risk-calculator --image-uri YOUR_ECR_URI --region us-east-1`.

### HTML Not Loading

```bash
# Check S3 file
aws s3 ls s3://jerome-dixon.io/uva/phts-risk-calculator/index.html

# Check bucket policy
aws s3api get-bucket-policy \
    --bucket jerome-dixon.io \
    --query Policy --output text | jq '.'
```

### Model Loading Errors

1. Verify models exist in container: `docker run --rm phts-risk-calculator:latest ls -la /var/task/models/`
2. Check IAM permissions for S3 access
3. Verify model file paths in Lambda code
4. Check Lambda logs in CloudWatch

---

## Verification Checklist

After deployment, verify:

- [ ] Lambda function is Active
- [ ] API Gateway returns 200 OK for `/metadata`
- [ ] HTML loads from S3
- [ ] Browser can call API (no CORS errors)
- [ ] Risk calculation works for all cohorts
- [ ] Causal factors are displayed
- [ ] Risk normalization is working

---

## Update Workflow

When updating models or code:

1. **Update Models**: Retrain → `python prepare_lambda_dir_phts.py`
2. **Rebuild Docker**: `./docker_build_phts.sh`
3. **Update Lambda**: `aws lambda update-function-code --image-uri ...`
4. **No API Gateway changes needed** (unless endpoints change)
5. **Update HTML if UI changes**: Upload to S3

---

## Rollback Procedure

If deployment fails:

```bash
# Rollback Lambda to previous image
aws lambda update-function-code \
    --function-name phts-risk-calculator \
    --image-uri PREVIOUS_ECR_URI

# Restore HTML from backup
cp phts_dashboard.html.backup phts_dashboard.html
aws s3 cp phts_dashboard.html \
    s3://jerome-dixon.io/uva/phts-risk-calculator/index.html \
    --content-type "text/html"
```

---

## Cost Optimization

1. **Lambda**: Use provisioned concurrency for consistent performance
2. **S3**: Enable lifecycle policies for old model versions
3. **API Gateway**: Use caching for metadata endpoints
4. **CloudFront**: Cache static assets (HTML, JS)

---

## Security Considerations

1. **CORS**: Currently allows all origins (`*`). For production, restrict to your domain
2. **API Keys**: Consider adding API key authentication
3. **Rate Limiting**: Configure throttling in API Gateway
4. **HTTPS**: Use CloudFront or API Gateway custom domain
5. **Data Privacy**: Ensure no PHI is logged or stored

---

## Production URLs

- **Dashboard**: `https://jerome-dixon.io/uva/phts-risk-calculator/`
- **API Gateway**: `https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod`
- **ECR Repository**: `535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator`

---

## References

- [AWS Lambda Container Images](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)
- [API Gateway Integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/getting-started-with-rest-apis.html)
- [S3 Static Website Hosting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)

---

**Last Updated**: 2026-01-13  
**Deployment Status**: ✅ Production
