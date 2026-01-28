#!/bin/bash
# Update Lambda function environment variables

set -e

# Configuration
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME:-phts-risk-calculator}
AWS_REGION=${AWS_REGION:-us-east-1}
API_GATEWAY_URL=${API_GATEWAY_URL:-""}
PHTS_BUCKET=${PHTS_BUCKET:-jerome-dixon.io}
S3_PREFIX=${S3_PREFIX:-uva/phts-risk-calculator}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Update Lambda Environment Variables${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Lambda function exists
echo -e "${YELLOW}Checking Lambda function...${NC}"
if ! aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo -e "${RED}Error: Lambda function not found: ${LAMBDA_FUNCTION_NAME}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Lambda function found${NC}"
echo ""

# Get current environment variables
echo -e "${YELLOW}Getting current environment variables...${NC}"
CURRENT_ENV=$(aws lambda get-function-configuration \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --region ${AWS_REGION} \
    --query 'Environment.Variables' \
    --output json)

echo "Current environment variables:"
echo "$CURRENT_ENV" | jq '.' || echo "$CURRENT_ENV"
echo ""

# If API_GATEWAY_URL not provided, try to get from API Gateway
if [ -z "$API_GATEWAY_URL" ]; then
    echo -e "${YELLOW}API_GATEWAY_URL not provided, attempting to discover from API Gateway...${NC}"
    
    # Try to find API Gateway by name first
    API_ID=$(aws apigateway get-rest-apis \
        --region ${AWS_REGION} \
        --query "items[?name=='phts-calculator-api'].id" \
        --output text 2>/dev/null || echo "")
    
    # If not found by name, try known API ID (359vxflbzj)
    if [ -z "$API_ID" ]; then
        echo "  Trying known API Gateway ID: 359vxflbzj"
        API_ID="359vxflbzj"
        # Verify it exists
        if ! aws apigateway get-rest-api --rest-api-id ${API_ID} --region ${AWS_REGION} &>/dev/null; then
            API_ID=""
        fi
    fi
    
    if [ -n "$API_ID" ]; then
        STAGE_NAME="prod"
        API_GATEWAY_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${STAGE_NAME}"
        echo -e "${GREEN}✓ Found API Gateway: ${API_GATEWAY_URL}${NC}"
    else
        echo -e "${YELLOW}⚠ API Gateway not found. Please provide API_GATEWAY_URL manually.${NC}"
        echo "Usage: API_GATEWAY_URL='https://API_ID.execute-api.REGION.amazonaws.com/prod' ./update_lambda_env.sh"
        exit 1
    fi
    echo ""
fi

# Build environment variables JSON
echo -e "${YELLOW}Preparing environment variables...${NC}"

# Parse current environment variables and merge with new ones
ENV_VARS=$(echo "$CURRENT_ENV" | jq -r --arg api_url "$API_GATEWAY_URL" \
    --arg bucket "$PHTS_BUCKET" \
    --arg prefix "$S3_PREFIX" \
    '. + {
        "API_GATEWAY_URL": $api_url,
        "PHTS_BUCKET": $bucket,
        "S3_PREFIX": $prefix
    }')

echo "New environment variables:"
echo "$ENV_VARS" | jq '.'
echo ""

# Update Lambda function configuration
echo -e "${YELLOW}Updating Lambda function configuration...${NC}"
# Create environment variables file for AWS CLI (use relative path for Windows compatibility)
TMP_ENV_FILE="./tmp_env_$$.json"
cat > ${TMP_ENV_FILE} <<EOF
{
  "Variables": $(echo "$ENV_VARS" | jq -c '.')
}
EOF

# Convert to absolute path for file:// syntax
ABS_ENV_FILE=$(cd $(dirname ${TMP_ENV_FILE}) && pwd)/$(basename ${TMP_ENV_FILE})
# On Windows/Git Bash, convert to forward slashes
ABS_ENV_FILE=$(echo "$ABS_ENV_FILE" | sed 's|\\|/|g')

aws lambda update-function-configuration \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --environment file://${ABS_ENV_FILE} \
    --region ${AWS_REGION} > /dev/null

rm -f ${TMP_ENV_FILE}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Lambda environment variables updated successfully${NC}"
else
    echo -e "${RED}Error: Failed to update Lambda environment variables${NC}"
    exit 1
fi
echo ""

# Wait for update to complete
echo -e "${YELLOW}Waiting for update to complete...${NC}"
aws lambda wait function-updated \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --region ${AWS_REGION}
echo -e "${GREEN}✓ Update complete${NC}"
echo ""

# Verify update
echo -e "${YELLOW}Verifying update...${NC}"
UPDATED_ENV=$(aws lambda get-function-configuration \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --region ${AWS_REGION} \
    --query 'Environment.Variables' \
    --output json)

echo "Updated environment variables:"
echo "$UPDATED_ENV" | jq '.'
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Update Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Environment Variables:"
echo "  API_GATEWAY_URL: ${API_GATEWAY_URL}"
echo "  PHTS_BUCKET: ${PHTS_BUCKET}"
echo "  S3_PREFIX: ${S3_PREFIX}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. The HTML page will automatically fetch API URL from /metadata endpoint"
echo "2. Or update HTML manually with:"
echo "   const LAMBDA_API_URL = '${API_GATEWAY_URL}';"
echo ""
