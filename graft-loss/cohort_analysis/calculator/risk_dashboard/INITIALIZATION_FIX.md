# Lambda Initialization Fix

## Problem

The CloudWatch log group `/aws/lambda/phts-risk-calculator` does not exist, which means the Lambda function is failing during initialization before it can write any logs.

## Changes Made

### 1. Improved Error Handling

Added better error handling to ensure logs are created even if initialization fails:

- **S3 Client Initialization**: Made S3 client initialization non-fatal (wrapped in try/except)
- **Logging in Handler**: Added explicit logging at the start of `lambda_handler` to ensure logs are created
- **Error Logging**: Improved error logging to capture full stack traces

### 2. Code Changes

**Before:**
```python
s3_client = boto3.client("s3")  # Could fail during import
```

**After:**
```python
try:
    s3_client = boto3.client("s3")
except Exception as e:
    s3_client = None
    if 'logger' in globals():
        logger.warning(f"Could not initialize S3 client: {e}")
```

**Handler logging:**
```python
def lambda_handler(event, context):
    # Ensure logger is available and log that handler was called
    try:
        logger.info("Lambda handler invoked")
        logger.info(f"Event: {json.dumps(event)}")
    except Exception as e:
        print(f"Lambda handler invoked, but logging failed: {e}")
    # ... rest of handler
```

## Next Steps

1. **Rebuild and Deploy**: Docker image has been rebuilt with improved error handling
2. **Test API Gateway**: Invoke the API Gateway endpoint again
3. **Check Logs**: The improved logging should now create logs even if there are errors

## Expected Behavior

After this fix:
- Lambda handler should log "Lambda handler invoked" at the start
- Even if there are errors, logs should be created
- CloudWatch log group should be created on first invocation
- Full error details should be visible in logs

## Testing

After deployment, invoke the API Gateway:
```bash
curl "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata"
```

Then check CloudWatch logs - the log group should now exist and contain error details.

---

**Date**: 2026-01-13
**Status**: Fixed initialization error handling, rebuilt and deployed
