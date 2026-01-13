# PHTS Lambda Docker/ECR Deployment Guide

This guide explains how to deploy the PHTS Risk Calculator Lambda function using Docker containers and ECR.

## Overview

The Lambda function is deployed as a container image that includes:
- Python runtime and dependencies
- Lambda function code
- Trained models (CatBoost, XGBoost, XGBoost RF)
- Dashboard data (causal factors)

**Advantages of container deployment:**
- Up to 10GB container size (vs 250MB zip limit)
- Faster cold starts (models pre-loaded)
- Easier dependency management
- Better for large model files

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Docker installed** and running
3. **Models trained** and saved to `calculator/outputs/models/`
4. **Dashboard data generated** in `calculator/outputs/shap_ffa/`

## Step-by-Step Deployment

### 1. Prepare Lambda Directory

This copies models and dashboard data into a directory structure for Docker:

```bash
cd graft-loss/cohort_analysis/calculator/risk_dashboard
python prepare_lambda_dir_phts.py
```

This creates `lambda_dir_phts/` with:
```
lambda_dir_phts/
├── models/
│   ├── CHD/
│   │   ├── catboost_model.cbm
│   │   ├── xgboost_model.ubj
│   │   ├── xgboost_rf_model.ubj
│   │   ├── best_model.txt
│   │   └── final_model_json/
│   ├── Combined/
│   └── Myocardio/
└── dashboard_data/
    ├── CHD/
    │   └── dashboard_data.json
    ├── Combined/
    │   └── dashboard_data.json
    └── Myocardio/
        └── dashboard_data.json
```

### 2. Build and Push Docker Image

Use the automated script:

```bash
chmod +x docker_build_phts.sh
./docker_build_phts.sh
```

Or manually:

```bash
# Build image
docker build -f Dockerfile.phts -t phts-risk-calculator:latest .

# Login to ECR
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-east-1
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Create ECR repository (if needed)
aws ecr create-repository \
    --repository-name phts-risk-calculator \
    --region ${AWS_REGION}

# Tag and push
docker tag phts-risk-calculator:latest ${ECR_REGISTRY}/phts-risk-calculator:latest
docker push ${ECR_REGISTRY}/phts-risk-calculator:latest
```

### 3. Create/Update Lambda Function

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
    --environment Variables="{PHTS_BUCKET=jerome-dixon.io,S3_PREFIX=uva/phts-risk-calculator}" \
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

### 4. Configure Lambda Settings

```bash
# Update environment variables
aws lambda update-function-configuration \
    --function-name phts-risk-calculator \
    --environment Variables="{PHTS_BUCKET=jerome-dixon.io,S3_PREFIX=uva/phts-risk-calculator}" \
    --timeout 60 \
    --memory-size 3008 \
    --region us-east-1
```

### 5. Set Up API Gateway

Create or update API Gateway to connect to Lambda:

```bash
# Create REST API (if needed)
API_ID=$(aws apigateway create-rest-api \
    --name phts-calculator-api \
    --query 'id' \
    --output text)

# Create resource and method
# (Use AWS Console or CloudFormation for full setup)
```

## Configuration

### Environment Variables

- `PHTS_BUCKET`: S3 bucket name (default: `jerome-dixon.io`)
- `S3_PREFIX`: S3 prefix path (default: `uva/phts-risk-calculator`)
- `MODEL_BASE_PATH`: Path to models in container (default: `/var/task/models`)
- `DASHBOARD_DATA_PATH`: Path to dashboard data (default: `/var/task/dashboard_data`)

### Lambda Settings

- **Runtime**: Container image (Python 3.11)
- **Memory**: 3008 MB (for large models)
- **Timeout**: 60 seconds
- **Handler**: `phts_lambda_function.lambda_handler`

## Directory Structure in Container

```
/var/task/
├── phts_lambda_function.py
├── models/
│   ├── CHD/
│   │   ├── catboost_model.cbm
│   │   ├── xgboost_model.ubj
│   │   └── ...
│   ├── Combined/
│   └── Myocardio/
└── dashboard_data/
    ├── CHD/
    │   └── dashboard_data.json
    ├── Combined/
    │   └── dashboard_data.json
    └── Myocardio/
        └── dashboard_data.json
```

## Model Loading Strategy

The Lambda function uses a two-tier loading strategy:

1. **Container filesystem (primary)**: Models are baked into the container at `/var/task/models/`
   - Fastest access (no network latency)
   - Available immediately on cold start
   - No S3 costs

2. **S3 fallback**: If models not found in container, load from S3
   - Useful for updates without rebuilding container
   - Slower (network latency)
   - Requires S3 permissions

## Updating Models

### Option 1: Rebuild Container (Recommended)

```bash
# Update models in outputs/models/
# Then rebuild and push
./docker_build_phts.sh
aws lambda update-function-code \
    --function-name phts-risk-calculator \
    --image-uri ${ECR_URI}
```

### Option 2: Update S3 Only

```bash
# Upload new models to S3
aws s3 sync calculator/outputs/models/ \
    s3://jerome-dixon.io/uva/phts-risk-calculator/models/

# Lambda will automatically use S3 models on next invocation
```

## Troubleshooting

### Container Too Large

If container exceeds 10GB:
1. Remove unused model variants (keep only best model)
2. Compress models (if supported)
3. Use S3 for less-frequently-used models

### Cold Start Too Slow

1. Increase memory (more memory = faster CPU)
2. Use provisioned concurrency
3. Optimize model loading (already cached after first load)

### Model Loading Errors

1. Check container logs in CloudWatch
2. Verify models exist in `/var/task/models/`
3. Check file permissions
4. Verify model file formats are correct

### ECR Push Fails

1. Verify AWS credentials
2. Check ECR repository exists
3. Verify IAM permissions for ECR push
4. Check Docker is running

## Cost Optimization

1. **Provisioned Concurrency**: For consistent performance (reduces cold starts)
2. **Reserved Capacity**: For predictable workloads
3. **S3 Lifecycle Policies**: Archive old model versions
4. **Container Caching**: Reuse layers when possible

## Security

1. **ECR Image Scanning**: Enabled by default
2. **IAM Roles**: Use least-privilege principle
3. **VPC**: Deploy Lambda in VPC if needed
4. **Secrets**: Use AWS Secrets Manager for sensitive data

## Monitoring

1. **CloudWatch Logs**: Monitor function logs
2. **CloudWatch Metrics**: Track invocations, errors, duration
3. **X-Ray**: Enable for distributed tracing
4. **Custom Metrics**: Track model performance

## Next Steps

1. Set up API Gateway integration
2. Configure CloudFront for HTTPS
3. Add authentication/authorization
4. Set up CI/CD pipeline for automated deployments
5. Configure monitoring and alerting
