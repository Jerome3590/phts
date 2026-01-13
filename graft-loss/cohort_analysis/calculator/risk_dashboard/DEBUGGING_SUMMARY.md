# Lambda Function Debugging Summary

## Current Status

✅ **Lambda Function**: Active and configured
✅ **IAM Role**: Has CloudWatch Logs permissions
✅ **API Gateway**: Invoking Lambda (returns 500 errors)
❌ **CloudWatch Logs**: Log group does not exist

## Problem

The Lambda function is being invoked but:
1. Returns 500 Internal Server Error
2. No CloudWatch logs are created
3. This suggests the function is failing during initialization (before it can write logs)

## IAM Role Permissions

The Lambda execution role (`phts-lambda-role`) has:
- ✅ `AWSLambdaBasicExecutionRole` - AWS managed policy with CloudWatch Logs permissions
- ✅ `phts-lambda-policy` - Custom policy with:
  - `logs:CreateLogGroup`
  - `logs:CreateLogStream`
  - `logs:PutLogEvents`
  - S3 read permissions

**Permissions are correct** - the issue is likely in the function code.

## Likely Causes

### 1. Import Errors
The Lambda function may be failing during module import:
- Missing dependencies in Docker image
- Import errors for numpy, pandas, catboost, xgboost
- Path issues with model libraries

### 2. Initialization Errors
Code may be failing during module-level execution:
- Model loading during import
- File path issues
- Missing environment variables

### 3. Container Issues
- Models/dashboard data not in correct location
- File permissions issues
- Path resolution problems

## Next Steps

### Option 1: Check AWS Console (Recommended)

1. **Lambda Console**:
   - Go to AWS Console > Lambda > Functions > phts-risk-calculator
   - Click "Monitor" tab
   - Click "View logs in CloudWatch" (this will show logs even if CLI can't access them)
   - Check for initialization errors

2. **CloudWatch Logs Console**:
   - Go to AWS Console > CloudWatch > Log groups
   - Search for "phts-risk-calculator"
   - Check if log group exists (may have different name or region)

### Option 2: Test Locally

Test the Docker container locally to see if it runs:
```bash
docker run --rm -it \
  -e PHTS_BUCKET=jerome-dixon.io \
  -e S3_PREFIX=uva/phts-risk-calculator \
  -e API_GATEWAY_URL=https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod \
  phts-risk-calculator:latest \
  python -c "import phts_lambda_function; print('Import successful')"
```

### Option 3: Add Debug Logging

Add explicit logging at the start of the Lambda function to see if it even gets to the handler:
```python
import logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)
logger.info("Lambda function starting...")
```

### Option 4: Check Container Contents

Verify the Docker image has all required files:
```bash
docker run --rm -it phts-risk-calculator:latest /bin/bash
# Inside container:
ls -la /var/task/
ls -la /var/task/models/
ls -la /var/task/dashboard_data/
python -c "import sys; print(sys.path)"
```

## Most Likely Issue

Based on the symptoms (500 error, no logs), the function is likely:
1. **Failing during import** - Missing dependencies or import errors
2. **Failing during initialization** - Code at module level that crashes
3. **Path issues** - Models/dashboard data not found

## Recommendation

**Use AWS Console** to check the logs - it's the most reliable way to see what's happening. The console will show:
- Initialization errors
- Import errors
- Runtime errors
- Stack traces

The CLI path issue with Git Bash is preventing us from seeing the logs, but the console will work.

---

**Last Checked**: 2026-01-13
**Status**: Lambda invoked but failing - need to check AWS Console for logs
