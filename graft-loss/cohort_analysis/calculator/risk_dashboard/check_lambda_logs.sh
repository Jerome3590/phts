#!/bin/bash
# Script to check Lambda CloudWatch logs
# Uses MSYS_NO_PATHCONV to prevent Git Bash from converting paths

export MSYS_NO_PATHCONV=1
LOG_GROUP="/aws/lambda/phts-risk-calculator"
REGION="us-east-1"

echo "Checking Lambda logs for: $LOG_GROUP"
echo ""

# Get latest log stream
echo "Getting latest log stream..."
LATEST_STREAM=$(aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --order-by LastEventTime \
  --descending \
  --max-items 1 \
  --query 'logStreams[0].logStreamName' \
  --output text 2>&1)

if [ $? -eq 0 ] && [ -n "$LATEST_STREAM" ] && [ "$LATEST_STREAM" != "None" ]; then
  echo "Latest log stream: $LATEST_STREAM"
  echo ""
  echo "Recent log events (last 100):"
  aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$LATEST_STREAM" \
    --region "$REGION" \
    --limit 100 \
    --query 'events[*].message' \
    --output text 2>&1 | tail -100
else
  echo "Error getting log stream: $LATEST_STREAM"
  echo ""
  echo "Trying to list all log groups..."
  aws logs describe-log-groups \
    --region "$REGION" \
    --log-group-name-prefix "/aws/lambda/phts" \
    --query 'logGroups[*].[logGroupName,creationTime]' \
    --output table 2>&1
fi

echo ""
echo "Checking for errors in last hour..."
START_TIME=$(($(date +%s) - 3600))000
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --start-time "$START_TIME" \
  --filter-pattern "ERROR" \
  --query 'events[*].message' \
  --output text 2>&1 | head -50
