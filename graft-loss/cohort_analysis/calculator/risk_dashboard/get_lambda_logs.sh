#!/bin/bash
# Script to get Lambda CloudWatch logs after API Gateway invocation

export MSYS_NO_PATHCONV=1
LOG_GROUP="/aws/lambda/phts-risk-calculator"
REGION="us-east-1"

echo "Checking CloudWatch logs for: $LOG_GROUP"
echo ""

# Get latest log stream
LATEST_STREAM=$(aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --order-by LastEventTime \
  --descending \
  --max-items 1 \
  --query 'logStreams[0].logStreamName' \
  --output text 2>&1)

if [ -n "$LATEST_STREAM" ] && [ "$LATEST_STREAM" != "None" ] && [ "$LATEST_STREAM" != "" ] && [[ ! "$LATEST_STREAM" =~ "error" ]] && [[ ! "$LATEST_STREAM" =~ "Error" ]]; then
  echo "✅ Found log stream: $LATEST_STREAM"
  echo ""
  echo "=========================================="
  echo "Recent log events (last 100):"
  echo "=========================================="
  aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$LATEST_STREAM" \
    --region "$REGION" \
    --limit 100 \
    --query 'events[*].message' \
    --output text 2>&1 | tail -100
  
  echo ""
  echo "=========================================="
  echo "ERROR level logs (last 50):"
  echo "=========================================="
  aws logs filter-log-events \
    --log-group-name "$LOG_GROUP" \
    --region "$REGION" \
    --start-time $(($(date +%s) - 600))000 \
    --filter-pattern "ERROR" \
    --query 'events[*].message' \
    --output text 2>&1 | head -50
else
  echo "❌ Log stream not found: $LATEST_STREAM"
  echo ""
  echo "This could mean:"
  echo "1. Lambda function hasn't been invoked yet"
  echo "2. Log group doesn't exist (will be created on first invocation)"
  echo "3. Lambda function failed before creating logs"
  echo ""
  echo "Try invoking the API Gateway endpoint first:"
  echo "  curl https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata"
fi
