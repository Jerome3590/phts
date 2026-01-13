# Quick Start: Docker/ECR Deployment

## Prerequisites Check

```bash
# Check AWS CLI
aws --version

# Check Docker
docker --version

# Check AWS credentials
aws sts get-caller-identity
```

## One-Command Deploy

```bash
cd graft-loss/cohort_analysis/calculator/risk_dashboard
./docker_build_phts.sh
```

This script will:
1. ✅ Prepare `lambda_dir_phts/` with models and data
2. ✅ Build Docker image
3. ✅ Login to ECR
4. ✅ Create ECR repository (if needed)
5. ✅ Tag and push image to ECR

## After Build: Create/Update Lambda

### Get ECR URI

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest"
echo $ECR_URI
```

### Create Lambda Function

```bash
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

### Update Existing Lambda

```bash
aws lambda update-function-code \
    --function-name phts-risk-calculator \
    --image-uri ${ECR_URI} \
    --region us-east-1
```

## Verify Deployment

```bash
# Test Lambda function
aws lambda invoke \
    --function-name phts-risk-calculator \
    --payload '{"httpMethod":"GET","path":"/metadata"}' \
    response.json

cat response.json
```

## Common Issues

### "No space left on device"
- Clean up Docker: `docker system prune -a`
- Remove old images: `docker image prune -a`

### "ECR repository not found"
- Script will create it automatically
- Or create manually: `aws ecr create-repository --repository-name phts-risk-calculator`

### "Permission denied"
- Check IAM permissions for ECR push
- Verify Docker is running: `docker ps`

## File Structure

```
risk_dashboard/
├── Dockerfile.phts              # Container definition
├── docker_build_phts.sh           # Build & deploy script
├── prepare_lambda_dir_phts.py     # Prepares models/data
├── phts_lambda_function.py        # Lambda handler
├── phts_requirements.txt          # Python dependencies
└── lambda_dir_phts/               # Created by prepare script
    ├── models/
    └── dashboard_data/
```

## Next Steps

1. Set up API Gateway
2. Update frontend HTML with API endpoint
3. Deploy frontend to S3
4. Test end-to-end
