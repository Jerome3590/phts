# Cohort Risk Dashboard Deployment Guide

Complete deployment guide for the AWS Lambda/S3-based cohort risk dashboard.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Infrastructure Setup](#infrastructure-setup)
4. [Model Preparation](#model-preparation)
5. [Lambda Function Deployment](#lambda-function-deployment)
6. [API Gateway Setup](#api-gateway-setup)
7. [S3 Static Site Deployment](#s3-static-site-deployment)
8. [Security Configuration](#security-configuration)
9. [Monitoring & Logging](#monitoring--logging)
10. [Testing](#testing)
11. [Troubleshooting](#troubleshooting)

## Architecture Overview

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ HTTPS
       ▼
┌─────────────────────────────────┐
│   CloudFront Distribution        │
│   (Custom Domain: dashboard.xyz) │
└──────┬───────────────────────────┘
       │
       ├─────────────────┐
       │                 │
       ▼                 ▼
┌─────────────┐   ┌──────────────┐
│  S3 Bucket  │   │ API Gateway   │
│ (Static Site)│   │  (REST API)   │
└─────────────┘   └──────┬────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │ Lambda (ECR) │
                  │  (Container) │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  S3 Bucket   │
                  │  (Models)    │
                  └──────────────┘
```

## Prerequisites

### AWS Account Setup

1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
3. **Docker** installed for building Lambda container
4. **Python 3.9+** for local development
5. **Node.js 18+** (optional, for frontend build tools)

### Required AWS Services

- Lambda (container-based)
- API Gateway (REST API)
- S3 (static site + model storage)
- CloudFront (CDN)
- IAM (roles and policies)
- CloudWatch (monitoring)
- ECR (container registry)

### Permissions Required

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:*",
        "apigateway:*",
        "s3:*",
        "cloudfront:*",
        "iam:*",
        "logs:*",
        "ecr:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Infrastructure Setup

### 1. Create S3 Buckets

```bash
# Models bucket (private)
aws s3 mb s3://uva-graft-loss-cohort-models --region us-east-1

# Static site bucket (public read)
aws s3 mb s3://uva-graft-loss-cohort-dashboard --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket uva-graft-loss-cohort-models \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket uva-graft-loss-cohort-models \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### 2. Create ECR Repository

```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name graft-loss-cohort-dashboard \
  --region us-east-1 \
  --image-scanning-configuration scanOnPush=true

# Get repository URI
REPO_URI=$(aws ecr describe-repositories \
  --repository-names graft-loss-cohort-dashboard \
  --query 'repositories[0].repositoryUri' \
  --output text)
echo "Repository URI: $REPO_URI"
```

### 3. Create IAM Roles

#### Lambda Execution Role

```bash
# Create role
aws iam create-role \
  --role-name GraftLossCohortLambdaRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach basic Lambda execution policy
aws iam attach-role-policy \
  --role-name GraftLossCohortLambdaRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create and attach S3 read policy
cat > lambda-s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:GetObject",
      "s3:ListBucket"
    ],
    "Resource": [
      "arn:aws:s3:::uva-graft-loss-cohort-models",
      "arn:aws:s3:::uva-graft-loss-cohort-models/*"
    ]
  }]
}
EOF

aws iam put-role-policy \
  --role-name GraftLossCohortLambdaRole \
  --policy-name S3ReadModels \
  --policy-document file://lambda-s3-policy.json
```

#### API Gateway Role (if using IAM auth)

```bash
# Create role for API Gateway
aws iam create-role \
  --role-name GraftLossCohortAPIRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }]
  }'
```

## Model Preparation

### 1. Convert R Models to Python-Compatible Format

Create `prepare_models.py`:

```python
#!/usr/bin/env python3
"""
Convert R models to Python-compatible format for Lambda deployment.
"""

import json
import boto3
import subprocess
from pathlib import Path

def convert_catboost_model(r_model_path, output_path):
    """Convert CatBoost R model to Python format."""
    # Use R script to export model
    r_script = f"""
    library(catboost)
    model <- readRDS("{r_model_path}")
    catboost.save_model(model, "{output_path}")
    """
    subprocess.run(["Rscript", "-e", r_script], check=True)

def convert_xgboost_model(r_model_path, output_path):
    """Convert XGBoost R model to Python format."""
    # XGBoost models are already compatible
    import shutil
    shutil.copy(r_model_path, output_path)

def upload_to_s3(local_path, s3_bucket, s3_key):
    """Upload model to S3."""
    s3 = boto3.client('s3')
    s3.upload_file(local_path, s3_bucket, s3_key)
    print(f"Uploaded {local_path} to s3://{s3_bucket}/{s3_key}")

def main():
    # Load model metadata from outputs
    outputs_dir = Path("outputs")
    
    # Process each cohort
    for cohort in ["CHD", "MyoCardio"]:
        # Find best model for cohort
        metrics_file = outputs_dir / "cohort_model_cindex_mc_cv_modifiable_clinical.csv"
        # ... load and determine best model ...
        
        # Convert and upload models
        # ...

if __name__ == "__main__":
    main()
```

### 2. Generate Metadata

Create `generate_metadata.py`:

```python
#!/usr/bin/env python3
"""
Generate metadata JSON for dashboard dropdowns and feature validation.
"""

import json
import pandas as pd
from pathlib import Path

def load_feature_ranges():
    """Load feature ranges from training data."""
    # Load from original data or outputs
    pass

def generate_metadata():
    """Generate complete metadata JSON."""
    metadata = {
        "cohorts": ["CHD", "MyoCardio"],
        "features": {},
        "models": {}
    }
    
    # Load feature information
    # Load model performance metrics
    # ...
    
    with open("metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)

if __name__ == "__main__":
    generate_metadata()
```

## Lambda Function Deployment

### 1. Create Lambda Function Structure

```
lambda/
├── Dockerfile
├── lambda_function.py
├── requirements.txt
├── models/
│   └── (downloaded from S3 at runtime)
└── utils/
    ├── model_loader.py
    └── predictor.py
```

### 2. Create Dockerfile

```dockerfile
FROM public.ecr.aws/lambda/python:3.9

# Install system dependencies
RUN yum install -y gcc g++ && \
    yum clean all

# Copy requirements and install Python dependencies
COPY requirements.txt ${LAMBDA_TASK_ROOT}
RUN pip install --no-cache-dir -r requirements.txt

# Copy function code
COPY lambda_function.py ${LAMBDA_TASK_ROOT}
COPY utils/ ${LAMBDA_TASK_ROOT}/utils/

# Set handler
CMD [ "lambda_function.handler" ]
```

### 3. Create Lambda Function Code

See `lambda_function.py` template in next section.

### 4. Build and Push Container

```bash
# Build
docker build -t graft-loss-cohort-dashboard:latest .

# Tag
docker tag graft-loss-cohort-dashboard:latest \
  ${REPO_URI}:latest

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin ${REPO_URI}

# Push
docker push ${REPO_URI}:latest
```

### 5. Create Lambda Function

```bash
# Create function
aws lambda create-function \
  --function-name graft-loss-cohort-dashboard \
  --package-type Image \
  --code ImageUri=${REPO_URI}:latest \
  --role arn:aws:iam::${ACCOUNT_ID}:role/GraftLossCohortLambdaRole \
  --timeout 30 \
  --memory-size 1024 \
  --environment Variables="{
    MODELS_BUCKET=uva-graft-loss-cohort-models,
    MODELS_PREFIX=models/
  }" \
  --region us-east-1
```

## API Gateway Setup

### 1. Create REST API

```bash
# Create API
API_ID=$(aws apigateway create-rest-api \
  --name graft-loss-cohort-api \
  --description "Cohort Risk Dashboard API" \
  --query 'id' \
  --output text)

echo "API ID: $API_ID"
```

### 2. Create Resources and Methods

```bash
# Create /metadata resource
METADATA_RESOURCE=$(aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $(aws apigateway get-resources --rest-api-id $API_ID --query 'items[0].id' --output text) \
  --path-part metadata \
  --query 'id' \
  --output text)

# Create GET method
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $METADATA_RESOURCE \
  --http-method GET \
  --authorization-type NONE

# Create /risk resource
RISK_RESOURCE=$(aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $(aws apigateway get-resources --rest-api-id $API_ID --query 'items[0].id' --output text) \
  --path-part risk \
  --query 'id' \
  --output text)

# Create POST method
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RISK_RESOURCE \
  --http-method POST \
  --authorization-type NONE
```

### 3. Configure CORS

```bash
# Enable CORS for all resources
aws apigateway put-method-response \
  --rest-api-id $API_ID \
  --resource-id $METADATA_RESOURCE \
  --http-method GET \
  --status-code 200 \
  --response-parameters method.response.header.Access-Control-Allow-Origin=true

aws apigateway put-integration-response \
  --rest-api-id $API_ID \
  --resource-id $METADATA_RESOURCE \
  --http-method GET \
  --status-code 200 \
  --response-parameters '{"method.response.header.Access-Control-Allow-Origin":"'"'"'*'"'"'"}'
```

### 4. Deploy API

```bash
# Create deployment
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod

# Get API URL
API_URL="https://${API_ID}.execute-api.us-east-1.amazonaws.com/prod"
echo "API URL: $API_URL"
```

## S3 Static Site Deployment

### 1. Upload Frontend Files

```bash
# Upload HTML, CSS, JS files
aws s3 sync frontend/ s3://uva-graft-loss-cohort-dashboard/ \
  --exclude "*.git/*" \
  --exclude "node_modules/*"

# Set index.html as default
aws s3 website s3://uva-graft-loss-cohort-dashboard/ \
  --index-document index.html \
  --error-document error.html
```

### 2. Configure Bucket Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::uva-graft-loss-cohort-dashboard/*"
  }]
}
```

### 3. Create CloudFront Distribution

```bash
# Create distribution
aws cloudfront create-distribution \
  --distribution-config file://cloudfront-config.json
```

## Security Configuration

### 1. API Authentication

**Option A: API Keys**
```bash
# Create API key
aws apigateway create-api-key \
  --name cohort-dashboard-key \
  --enabled

# Create usage plan
aws apigateway create-usage-plan \
  --name cohort-dashboard-plan \
  --api-stages apiId=$API_ID,stage=prod
```

**Option B: IAM Authentication**
- Configure API Gateway to use IAM
- Create IAM users/roles with appropriate policies

**Option C: Cognito**
- Set up Cognito User Pool
- Configure API Gateway authorizer

### 2. S3 Bucket Policies

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:role/GraftLossCohortLambdaRole"
      },
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::uva-graft-loss-cohort-models",
        "arn:aws:s3:::uva-graft-loss-cohort-models/*"
      ]
    }
  ]
}
```

### 3. Encryption

- **S3**: Server-side encryption (SSE-S3 or SSE-KMS)
- **API Gateway**: HTTPS only
- **Lambda**: Environment variables encrypted with KMS (if needed)

## Monitoring & Logging

### 1. CloudWatch Logs

Lambda automatically logs to CloudWatch. Create log groups:

```bash
aws logs create-log-group \
  --log-group-name /aws/lambda/graft-loss-cohort-dashboard
```

### 2. CloudWatch Metrics

Create custom metrics dashboard:

```bash
# Create dashboard
aws cloudwatch put-dashboard \
  --dashboard-name CohortDashboardMetrics \
  --dashboard-body file://dashboard-config.json
```

### 3. Alarms

```bash
# High error rate alarm
aws cloudwatch put-metric-alarm \
  --alarm-name CohortDashboardHighErrors \
  --alarm-description "Alert on high error rate" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold
```

## Testing

### 1. Test Lambda Locally

```bash
# Use Lambda runtime interface emulator
docker run -p 9000:8080 \
  -e MODELS_BUCKET=uva-graft-loss-cohort-models \
  graft-loss-cohort-dashboard:latest

# Test endpoint
curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d '{"path": "/metadata", "httpMethod": "GET"}'
```

### 2. Test API Gateway

```bash
# Test metadata endpoint
curl -X GET "${API_URL}/metadata"

# Test risk endpoint
curl -X POST "${API_URL}/risk" \
  -H "Content-Type: application/json" \
  -d '{
    "cohort": "CHD",
    "features": {"txcreat_r": 1.2, "txpalb_r": 3.5}
  }'
```

### 3. Test Frontend

```bash
# Serve locally
cd frontend/
python -m http.server 8000

# Open http://localhost:8000
# Update API_URL in config.js to point to your API Gateway
```

## Troubleshooting

### Common Issues

1. **Lambda Timeout**
   - Increase timeout (max 15 minutes)
   - Optimize model loading (cache models)
   - Use provisioned concurrency

2. **Cold Start Latency**
   - Use provisioned concurrency
   - Optimize container size
   - Pre-warm Lambda functions

3. **CORS Errors**
   - Verify CORS headers in API Gateway
   - Check browser console for specific errors
   - Ensure OPTIONS method is configured

4. **Model Loading Errors**
   - Verify S3 bucket permissions
   - Check model file paths
   - Verify model format compatibility

5. **API Gateway 502 Errors**
   - Check Lambda function logs
   - Verify integration configuration
   - Check Lambda timeout settings

### Debug Commands

```bash
# View Lambda logs
aws logs tail /aws/lambda/graft-loss-cohort-dashboard --follow

# Test Lambda directly
aws lambda invoke \
  --function-name graft-loss-cohort-dashboard \
  --payload '{"path": "/metadata", "httpMethod": "GET"}' \
  response.json

# Check API Gateway logs
aws apigateway get-gateway-responses --rest-api-id $API_ID
```

## Cost Optimization

1. **Lambda**: Use appropriate memory allocation (start with 512MB)
2. **API Gateway**: Enable caching for metadata endpoint
3. **CloudFront**: Use compression and caching
4. **S3**: Use lifecycle policies for old model versions
5. **Provisioned Concurrency**: Only if needed for low latency

## Next Steps

1. Set up CI/CD pipeline (GitHub Actions, CodePipeline)
2. Implement authentication/authorization
3. Add rate limiting
4. Set up automated testing
5. Create monitoring dashboards
6. Document API endpoints (OpenAPI/Swagger)

