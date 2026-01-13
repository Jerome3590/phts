#!/bin/bash
# Script to invoke Lambda and check logs

export MSYS_NO_PATHCONV=1
FUNCTION_NAME="phts-risk-calculator"
REGION="us-east-1"
LOG_GROUP="/aws/lambda/$FUNCTION_NAME"

echo "Invoking Lambda function: $FUNCTION_NAME"
echo ""

# Create test payload
cat > /tmp/test_payload.json <<'EOF'
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
echo "Invoking Lambda..."
aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --payload file:///tmp/test_payload.json \
  /tmp/lambda_response.json \
  2>&1

echo ""
echo "Response:"
cat /tmp/lambda_response.json 2>/dev/null | python -m json.tool 2>&1 | head -30

echo ""
echo "Waiting 3 seconds for logs to appear..."
sleep 3

echo ""
echo "Checking for log group: $LOG_GROUP"
aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --order-by LastEventTime \
  --descending \
  --max-items 1 \
  --query 'logStreams[0].logStreamName' \
  --output text 2>&1

LATEST_STREAM=$(aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --order-by LastEventTime \
  --descending \
  --max-items 1 \
  --query 'logStreams[0].logStreamName' \
  --output text 2>&1)

if [ -n "$LATEST_STREAM" ] && [ "$LATEST_STREAM" != "None" ] && [ "$LATEST_STREAM" != "" ] && [[ ! "$LATEST_STREAM" =~ "error" ]]; then
  echo ""
  echo "Found log stream: $LATEST_STREAM"
  echo ""
  echo "Recent log events:"
  echo "----------------------------------------"
  aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$LATEST_STREAM" \
    --region "$REGION" \
    --limit 100 \
    --query 'events[*].message' \
    --output text 2>&1 | tail -100
else
  echo ""
  echo "No log stream found. This could mean:"
  echo "1. Lambda function hasn't been invoked yet"
  echo "2. Lambda function failed before creating logs"
  echo "3. Log group doesn't exist (will be created on first invocation)"
  echo ""
  echo "Checking Lambda function configuration..."
  aws lambda get-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --query '[FunctionName,State,LastUpdateStatus,CodeSize]' \
    --output table 2>&1
fi
