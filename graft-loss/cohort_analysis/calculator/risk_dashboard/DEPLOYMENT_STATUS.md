# PHTS Dashboard Deployment Status

## ✅ Completed Steps

1. **All Cohorts Trained**:
   - CHD: Models + Dashboard data ✅
   - Combined: Models + Dashboard data ✅
   - Myocardio: Models + Dashboard data ✅

2. **Docker Image Built**:
   - Image: `phts-risk-calculator:latest` (2.47GB)
   - Includes all 3 cohorts
   - Docker format (Lambda compatible) ✅

3. **ECR Push Complete**:
   - Repository: `535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest`
   - Image pushed successfully ✅

4. **Lambda Function Updated**:
   - Function: `phts-risk-calculator`
   - State: Active ✅
   - Last Update: Successful ✅
   - Package Type: Image ✅

## ⚠️ Current Issue

**API Gateway returning "Internal server error"**

The Lambda function is Active but API calls are failing. Possible causes:
1. Lambda function initialization error (imports, model loading)
2. Path issues with models/dashboard data in container
3. Missing dependencies or environment variables

## Next Steps to Debug

### Option 1: Check CloudWatch Logs (Recommended)

Use AWS Console or CLI to check Lambda logs:
```bash
# In AWS Console:
# CloudWatch > Log groups > /aws/lambda/phts-risk-calculator

# Or via CLI (if path escaping works):
aws logs tail "/aws/lambda/phts-risk-calculator" --region us-east-1 --follow
```

### Option 2: Test Lambda Directly

Create a test event and invoke Lambda:
```bash
# Create test event
cat > test_event.json <<'EOF'
{
  "httpMethod": "GET",
  "path": "/metadata",
  "queryStringParameters": null,
  "requestContext": {
    "domainName": "359vxflbzj.execute-api.us-east-1.amazonaws.com",
    "stage": "prod"
  }
}
EOF

# Invoke Lambda
aws lambda invoke \
  --function-name phts-risk-calculator \
  --region us-east-1 \
  --payload file://test_event.json \
  response.json

# Check response
cat response.json | python -m json.tool
```

### Option 3: Verify Container Contents

Test locally if Docker image has correct structure:
```bash
docker run --rm -it phts-risk-calculator:latest /bin/bash
# Inside container:
ls -la /var/task/models/
ls -la /var/task/dashboard_data/
python -c "import phts_lambda_function; print('Import successful')"
```

## Files Updated

- `phts_lambda_function.py`: Updated `COHORTS_WITH_DATA` to include all 3 cohorts
- Added improved error handling and logging
- Docker image rebuilt and pushed

## Deployment Commands Used

```bash
# Build Docker image
DOCKER_BUILDKIT=0 docker build -f Dockerfile.phts -t phts-risk-calculator:latest .

# Push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 535362115856.dkr.ecr.us-east-1.amazonaws.com
docker tag phts-risk-calculator:latest 535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest
docker push 535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest

# Update Lambda
aws lambda update-function-code \
  --function-name phts-risk-calculator \
  --image-uri 535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest \
  --region us-east-1
```

## API Endpoints

- **API Gateway**: `https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod`
- **Metadata**: `GET /metadata` or `GET /metadata?cohort=CHD`
- **Risk**: `POST /risk`
- **Causal**: `POST /causal`

---

**Last Updated**: 2026-01-13
**Status**: Docker image built and Lambda updated, but API returning errors (needs debugging)
