# PHTS Dashboard Deployment Workflow

## Overview

Complete step-by-step deployment workflow for the PHTS Risk Calculator Dashboard.

## Deployment Order

1. **Prepare Models & Data** (Local)
2. **Build & Push Docker Image to ECR**
3. **Create/Update Lambda Function** (from ECR image)
4. **Set Up API Gateway** (connects to Lambda)
5. **Update Lambda Environment Variables** (with API Gateway URL)
6. **Inject API URL into HTML** (for frontend)
7. **Upload HTML to S3** (static website)

## Prerequisites

```bash
# Verify AWS CLI is configured
aws sts get-caller-identity

# Verify Docker is running
docker ps

# Verify you're in the correct directory
cd graft-loss/cohort_analysis/calculator/risk_dashboard
```

## Step-by-Step Deployment

### Step 1: Prepare Models and Data for Lambda

**Purpose**: Copy models and dashboard data into directory structure for Docker container.

```bash
python prepare_lambda_dir_phts.py
```

**What it does**:
- Creates `lambda_dir_phts/` directory
- Copies models from `../outputs/models/` to `lambda_dir_phts/models/`
- Copies dashboard data from `../outputs/shap_ffa/` to `lambda_dir_phts/dashboard_data/`
- Validates structure

**Output**: `lambda_dir_phts/` directory ready for Docker build

---

### Step 2: Build and Push Docker Image to ECR

**Purpose**: Create container image with Lambda function, dependencies, models, and data.

```bash
./docker_build_phts.sh
```

**What it does**:
1. Validates `lambda_dir_phts/` exists
2. Builds Docker image using `Dockerfile.phts`
3. Logs into ECR
4. Creates ECR repository (if needed)
5. Tags image for ECR
6. Pushes image to ECR

**Output**: ECR image URI (e.g., `ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/phts-risk-calculator:latest`)

**Note**: Save the ECR URI for Step 3.

---

### Step 3: Create/Update Lambda Function

**Purpose**: Deploy Lambda function using the container image from ECR.

#### Option A: Create New Lambda Function

```bash
# Get ECR URI (from Step 2 output or manually)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest"

# Create Lambda function
aws lambda create-function \
    --function-name phts-risk-calculator \
    --package-type Image \
    --code ImageUri=${ECR_URI} \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/phts-lambda-role \
    --timeout 60 \
    --memory-size 3008 \
    --region us-east-1
```

#### Option B: Update Existing Lambda Function

```bash
# Get ECR URI
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest"

# Update Lambda function code
aws lambda update-function-code \
    --function-name phts-risk-calculator \
    --image-uri ${ECR_URI} \
    --region us-east-1
```

**What it does**:
- Creates or updates Lambda function
- Uses container image from ECR
- Configures basic settings (timeout, memory)

**Output**: Lambda function ARN

---

### Step 4: Set Up API Gateway

**Purpose**: Create REST API that connects to Lambda function.

```bash
./setup_api_gateway.sh
```

**What it does**:
1. Creates REST API (or uses existing)
2. Creates resources: `/metadata`, `/risk`, `/causal`
3. Creates methods: GET for `/metadata`, POST for `/risk` and `/causal`
4. Configures Lambda integration (proxy integration)
5. Sets up CORS (OPTIONS methods)
6. Grants API Gateway permission to invoke Lambda
7. Deploys API to `prod` stage
8. **Automatically updates Lambda environment variable with API URL**

**Output**: API Gateway URL (e.g., `https://API_ID.execute-api.REGION.amazonaws.com/prod`)

**Note**: This script automatically sets `API_GATEWAY_URL` in Lambda environment variables.

---

### Step 5: Update Lambda Environment Variables (if needed)

**Purpose**: Ensure Lambda has correct configuration.

**Note**: Usually done automatically by `setup_api_gateway.sh`, but can be done manually:

```bash
# If API Gateway URL changed or needs manual update
API_GATEWAY_URL='https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod' \
  ./update_lambda_env.sh
```

**What it does**:
- Gets current Lambda environment variables
- Merges with new values
- Updates Lambda function configuration
- Verifies update

**Environment Variables Set**:
- `API_GATEWAY_URL`: API Gateway endpoint URL
- `PHTS_BUCKET`: `jerome-dixon.io`
- `S3_PREFIX`: `uva/phts-risk-calculator`

---

### Step 6: Inject API URL into HTML

**Purpose**: Update HTML file with correct API Gateway URL.

```bash
# Get API URL from Lambda or provide manually
API_GATEWAY_URL='https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod' \
  ./inject_api_url_to_html.sh
```

**What it does**:
1. Gets API URL from Lambda environment variable (or uses provided)
2. Creates backup of HTML file
3. Injects API URL into HTML (updates `LAMBDA_API_URL` and `window.LAMBDA_API_URL`)
4. Verifies injection

**Output**: Updated `phts_dashboard.html` with correct API URL

---

### Step 7: Upload HTML to S3

**Purpose**: Deploy frontend to S3 static website hosting.

#### Option A: Using Injection Script (Recommended)

```bash
# Inject API URL and upload in one step
API_GATEWAY_URL='https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod' \
  UPLOAD_TO_S3=true \
  ./inject_api_url_to_html.sh
```

#### Option B: Manual Upload

```bash
# Upload HTML to S3
aws s3 cp phts_dashboard.html \
    s3://jerome-dixon.io/uva/phts-risk-calculator/index.html \
    --content-type "text/html" \
    --region us-east-1
```

**What it does**:
- Uploads HTML file to S3
- Sets correct content type
- Makes file publicly accessible (if bucket policy allows)

**Output**: Dashboard accessible at S3 URL

---

## Complete Automated Workflow

```bash
#!/bin/bash
# Complete deployment script

set -e

echo "=== PHTS Dashboard Deployment ==="
echo ""

# Step 1: Prepare models and data
echo "Step 1: Preparing models and data..."
python prepare_lambda_dir_phts.py
echo ""

# Step 2: Build and push Docker image
echo "Step 2: Building and pushing Docker image..."
./docker_build_phts.sh
ECR_URI=$(aws ecr describe-repositories \
    --repository-names phts-risk-calculator \
    --query 'repositories[0].repositoryUri' \
    --output text):latest
echo "ECR URI: ${ECR_URI}"
echo ""

# Step 3: Update Lambda function
echo "Step 3: Updating Lambda function..."
aws lambda update-function-code \
    --function-name phts-risk-calculator \
    --image-uri ${ECR_URI} \
    --region us-east-1 > /dev/null
echo "Waiting for Lambda update..."
aws lambda wait function-updated \
    --function-name phts-risk-calculator \
    --region us-east-1
echo "✓ Lambda updated"
echo ""

# Step 4: Set up API Gateway
echo "Step 4: Setting up API Gateway..."
./setup_api_gateway.sh
API_URL=$(aws apigateway get-rest-apis \
    --query "items[?name=='phts-calculator-api'].id" \
    --output text | xargs -I {} echo "https://{}.execute-api.us-east-1.amazonaws.com/prod")
echo "API URL: ${API_URL}"
echo ""

# Step 5: Inject API URL and upload HTML
echo "Step 5: Injecting API URL and uploading HTML..."
API_GATEWAY_URL="${API_URL}" \
  UPLOAD_TO_S3=true \
  ./inject_api_url_to_html.sh
echo ""

echo "=== Deployment Complete ==="
echo "Dashboard URL: https://jerome-dixon.io/uva/phts-risk-calculator/"
echo "API URL: ${API_URL}"
```

## Quick Reference

### One-Command Deployment

```bash
# Full deployment (after initial setup)
./deploy_complete.sh  # (create this script from workflow above)
```

### Individual Steps

```bash
# Step 1: Prepare
python prepare_lambda_dir_phts.py

# Step 2: Build Docker
./docker_build_phts.sh

# Step 3: Update Lambda
aws lambda update-function-code \
    --function-name phts-risk-calculator \
    --image-uri $(aws ecr describe-repositories --repository-names phts-risk-calculator --query 'repositories[0].repositoryUri' --output text):latest

# Step 4: API Gateway
./setup_api_gateway.sh

# Step 5: Deploy HTML
API_GATEWAY_URL='https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod' \
  UPLOAD_TO_S3=true \
  ./inject_api_url_to_html.sh
```

## Verification

After deployment, verify each component:

### 1. Verify Lambda Function

```bash
aws lambda get-function \
    --function-name phts-risk-calculator \
    --query 'Configuration.[FunctionName,LastModified,State]' \
    --output table
```

### 2. Verify API Gateway

```bash
# Test metadata endpoint
curl 'https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod/metadata?cohort=Combined'
```

### 3. Verify S3 HTML

```bash
# Check if file exists
aws s3 ls s3://jerome-dixon.io/uva/phts-risk-calculator/index.html

# Test in browser
open https://jerome-dixon.io/uva/phts-risk-calculator/
```

### 4. End-to-End Test

1. Open dashboard in browser
2. Select cohort
3. Enter clinical features
4. Click "Calculate Risk"
5. Verify risk score and causal factors are displayed

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
# Check API Gateway deployment
aws apigateway get-deployments \
    --rest-api-id YOUR_API_ID \
    --query 'items[-1]'

# Test API directly
curl -X POST 'https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod/risk' \
  -H 'Content-Type: application/json' \
  -d '{"cohort":"Combined","features":{"egfr_tx":60.0}}'
```

### HTML Not Loading

```bash
# Check S3 file
aws s3 ls s3://jerome-dixon.io/uva/phts-risk-calculator/

# Check bucket policy
aws s3api get-bucket-policy \
    --bucket jerome-dixon.io \
    --query Policy --output text | jq '.'
```

## Update Workflow

When updating models or code:

1. **Update Models**: Retrain models → `python prepare_lambda_dir_phts.py`
2. **Rebuild Docker**: `./docker_build_phts.sh`
3. **Update Lambda**: `aws lambda update-function-code --image-uri ...`
4. **No API Gateway changes needed** (unless endpoints change)
5. **No HTML changes needed** (unless UI changes)

## Rollback

If deployment fails:

```bash
# Rollback Lambda to previous version
aws lambda update-function-code \
    --function-name phts-risk-calculator \
    --image-uri PREVIOUS_ECR_URI

# Restore HTML from backup
cp phts_dashboard.html.backup phts_dashboard.html
aws s3 cp phts_dashboard.html \
    s3://jerome-dixon.io/uva/phts-risk-calculator/index.html \
    --content-type "text/html"
```
