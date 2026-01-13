# Lambda Error Debugging

## Current Status

- ✅ Lambda function is Active and being invoked
- ✅ Route matching is working (GET requests are reaching the handler)
- ❌ Function returns 500 "Internal server error"
- ❌ Error details not visible in API response

## What We've Done

1. **Improved Error Handling**: Added comprehensive error logging and traceback capture
2. **Path Matching**: Fixed route matching to handle empty paths (GET fallback to /metadata)
3. **Defensive Coding**: Added try/except blocks at multiple levels
4. **Enhanced Logging**: Added detailed logging throughout the handler

## Next Steps - Check CloudWatch Logs

Since the API response doesn't show error details (API Gateway may be stripping them), you need to check CloudWatch logs in the AWS Console:

### Steps:

1. **Go to AWS Console** > CloudWatch > Log groups
2. **Search for**: `/aws/lambda/phts-risk-calculator`
3. **Click on the log group** (it should exist now since Lambda is being invoked)
4. **Click on the latest log stream**
5. **Look for**:
   - `ERROR` level logs
   - `Traceback` messages
   - `Error in lambda_handler` or `Error in handle_metadata` messages

### What to Look For:

The logs should show:
- "Lambda handler invoked" - confirms handler is called
- "Matched GET /metadata route" - confirms routing works
- "handle_metadata called" - confirms function entry
- Error messages with full tracebacks

### Common Issues to Check:

1. **File Not Found**: Dashboard data files not in container
   - Look for: `FileNotFoundError` or `Dashboard data not found`
   - Solution: Verify `lambda_dir_phts/dashboard_data/` has all cohort folders

2. **Import Errors**: Missing dependencies
   - Look for: `ImportError` or `ModuleNotFoundError`
   - Solution: Check Dockerfile installs all requirements

3. **Path Issues**: Files not in expected locations
   - Look for: Path-related errors in `load_dashboard_data`
   - Solution: Verify Dockerfile copies files correctly

4. **JSON Parsing Errors**: Invalid dashboard data files
   - Look for: `JSONDecodeError` or `ValueError`
   - Solution: Verify dashboard_data.json files are valid JSON

## Quick Test

After checking logs, you can also test by invoking Lambda directly:

```bash
aws lambda invoke \
  --function-name phts-risk-calculator \
  --region us-east-1 \
  --payload '{"httpMethod":"GET","path":"/metadata"}' \
  response.json

cat response.json | python -m json.tool
```

This bypasses API Gateway and shows the raw Lambda response.

---

**Status**: Waiting for CloudWatch log inspection to identify root cause
