# Docker Desktop Issue - Next Steps

## Current Status

✅ **All Training Complete**:
- CHD: Models + Dashboard data ✅
- Combined: Models + Dashboard data ✅
- Myocardio: Models + Dashboard data ✅

✅ **Lambda Directory Prepared**:
- 9 model files (all cohorts)
- 3 dashboard data files (all cohorts)

⚠️ **Docker Desktop Issue**:
- Docker Desktop is returning 500 errors
- Cannot rebuild Docker image at this time
- Lambda function is Active but may be using old image (only Combined cohort)

## Issue

Docker Desktop API is returning 500 errors:
```
request returned 500 Internal Server Error for API route and version 
http://%2F%2F.%2Fpipe%2FdockerDesktopLinuxEngine/v1.52/...
```

## Solution

**Restart Docker Desktop**:
1. Close Docker Desktop completely
2. Restart Docker Desktop
3. Wait for it to fully start
4. Then rebuild and push:

```bash
cd graft-loss/cohort_analysis/calculator/risk_dashboard

# Rebuild Docker image
./docker_build_phts.sh

# Or manually:
DOCKER_BUILDKIT=0 docker build -f Dockerfile.phts -t phts-risk-calculator:latest .
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 535362115856.dkr.ecr.us-east-1.amazonaws.com
docker tag phts-risk-calculator:latest 535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest
docker push 535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest

# Update Lambda
aws lambda update-function-code \
  --function-name phts-risk-calculator \
  --image-uri 535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest \
  --region us-east-1

# Wait for update
aws lambda wait function-updated \
  --function-name phts-risk-calculator \
  --region us-east-1

# Test
curl "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata?cohort=CHD"
```

## Alternative: Use Existing Image

If Docker Desktop continues to have issues, you can:
1. Use the existing Lambda function (currently has Combined cohort)
2. Manually upload models to S3 and have Lambda load from S3
3. Use a different machine/CI pipeline to build the Docker image

## Verification After Rebuild

After Docker rebuild and Lambda update, verify:

```bash
# Test all cohorts
curl "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata?cohort=CHD"
curl "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata?cohort=Combined"
curl "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata?cohort=Myocardio"
```

All should return causal factors for their respective cohorts.

## Current Lambda Status

- **State**: Active ✅
- **Last Update**: Successful ✅
- **Image**: May be using old image (only Combined cohort)
- **API**: Returning errors (likely due to missing cohorts in current image)

Once Docker is rebuilt with all cohorts, the Lambda update should resolve the API errors.
