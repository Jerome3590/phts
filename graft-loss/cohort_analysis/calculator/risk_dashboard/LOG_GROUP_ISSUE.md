# CloudWatch Log Group Issue

## Problem

The API Gateway is returning 500 errors, but the CloudWatch log group `/aws/lambda/phts-risk-calculator` does not exist even after invoking the Lambda function.

## Possible Causes

1. **Lambda function failing during initialization** - If the function crashes during import/initialization before it can write logs, the log group may not be created
2. **IAM Role missing CloudWatch Logs permissions** - The Lambda execution role may not have permission to create log groups
3. **Lambda function not actually being invoked** - API Gateway might be failing before reaching Lambda
4. **Log group creation delay** - Sometimes there's a delay in log group creation

## What We Know

- ✅ Lambda function exists and is Active
- ✅ API Gateway is configured and returning responses (500 errors)
- ❌ CloudWatch log group does not exist
- ❌ Cannot see error logs

## Next Steps

### 1. Check Lambda IAM Role Permissions

The Lambda execution role needs these permissions:
- `logs:CreateLogGroup`
- `logs:CreateLogStream`
- `logs:PutLogEvents`

Check the role:
```bash
aws lambda get-function-configuration \
  --function-name phts-risk-calculator \
  --region us-east-1 \
  --query 'Role' \
  --output text
```

Then check the role's policies:
```bash
ROLE_NAME=$(aws lambda get-function-configuration --function-name phts-risk-calculator --region us-east-1 --query 'Role' --output text | awk -F'/' '{print $NF}')
aws iam list-attached-role-policies --role-name "$ROLE_NAME"
```

### 2. Check AWS Console

1. Go to AWS Console > Lambda > Functions > phts-risk-calculator
2. Click on "Monitor" tab
3. Check "Invocations" and "Errors" metrics
4. Click "View logs in CloudWatch" - this will show if logs exist

### 3. Check API Gateway Logs

API Gateway might have its own logs:
```bash
aws apigateway get-rest-apis --query "items[?name=='phts-calculator-api']"
```

### 4. Test Lambda Directly

Try invoking Lambda directly (not through API Gateway) to see if it creates logs:
```bash
aws lambda invoke \
  --function-name phts-risk-calculator \
  --region us-east-1 \
  --payload '{"httpMethod":"GET","path":"/metadata"}' \
  response.json
```

## Recommendation

**Use AWS Console** to check:
1. Lambda function > Monitor tab > View logs in CloudWatch
2. CloudWatch > Log groups (search for "phts")
3. Lambda function > Configuration > Permissions (check IAM role)

The console will show logs even if the CLI has path issues.
