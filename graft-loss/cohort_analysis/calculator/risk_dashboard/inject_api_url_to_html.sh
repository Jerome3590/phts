#!/bin/bash
# Inject API Gateway URL into HTML before uploading to S3

set -e

# Configuration
API_GATEWAY_URL=${API_GATEWAY_URL:-""}
HTML_FILE=${HTML_FILE:-phts_dashboard.html}
OUTPUT_FILE=${OUTPUT_FILE:-phts_dashboard.html}
S3_BUCKET=${S3_BUCKET:-jerome-dixon.io}
S3_PREFIX=${S3_PREFIX:-uva/phts-risk-calculator}
AWS_REGION=${AWS_REGION:-us-east-1}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Inject API URL into HTML${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# If API_GATEWAY_URL not provided, try to get from Lambda
if [ -z "$API_GATEWAY_URL" ]; then
    echo -e "${YELLOW}API_GATEWAY_URL not provided, attempting to get from Lambda...${NC}"
    
    LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME:-phts-risk-calculator}
    
    # Get API URL from Lambda environment variable
    API_GATEWAY_URL=$(aws lambda get-function-configuration \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --region ${AWS_REGION} \
        --query 'Environment.Variables.API_GATEWAY_URL' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$API_GATEWAY_URL" ] || [ "$API_GATEWAY_URL" == "None" ]; then
        # Try to get from API Gateway by name first
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
            echo -e "${RED}Error: Could not determine API Gateway URL${NC}"
            echo "Please provide API_GATEWAY_URL environment variable"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Got API URL from Lambda: ${API_GATEWAY_URL}${NC}"
    fi
    echo ""
fi

# Check if HTML file exists
if [ ! -f "$HTML_FILE" ]; then
    echo -e "${RED}Error: HTML file not found: ${HTML_FILE}${NC}"
    exit 1
fi

# Create backup
BACKUP_FILE="${HTML_FILE}.backup"
cp "$HTML_FILE" "$BACKUP_FILE"
echo -e "${GREEN}✓ Created backup: ${BACKUP_FILE}${NC}"

# Inject API URL into HTML
echo -e "${YELLOW}Injecting API URL into HTML...${NC}"

# Use sed to replace the API URL (works on both Linux and macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s|const LAMBDA_API_URL = .*;|const LAMBDA_API_URL = '${API_GATEWAY_URL}';|g" "$HTML_FILE"
    sed -i '' "s|window.LAMBDA_API_URL = .*;|window.LAMBDA_API_URL = '${API_GATEWAY_URL}';|g" "$HTML_FILE"
else
    # Linux
    sed -i "s|const LAMBDA_API_URL = .*;|const LAMBDA_API_URL = '${API_GATEWAY_URL}';|g" "$HTML_FILE"
    sed -i "s|window.LAMBDA_API_URL = .*;|window.LAMBDA_API_URL = '${API_GATEWAY_URL}';|g" "$HTML_FILE"
fi

# Also set as window variable for easy access
if ! grep -q "window.LAMBDA_API_URL" "$HTML_FILE"; then
    # Add window variable after the const declaration
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "/const LAMBDA_API_URL/a\\
    window.LAMBDA_API_URL = '${API_GATEWAY_URL}';
" "$HTML_FILE"
    else
        sed -i "/const LAMBDA_API_URL/a\\
    window.LAMBDA_API_URL = '${API_GATEWAY_URL}';
" "$HTML_FILE"
    fi
fi

echo -e "${GREEN}✓ API URL injected: ${API_GATEWAY_URL}${NC}"
echo ""

# Verify injection
if grep -q "${API_GATEWAY_URL}" "$HTML_FILE"; then
    echo -e "${GREEN}✓ Verification: API URL found in HTML${NC}"
else
    echo -e "${RED}⚠ Warning: API URL not found in HTML after injection${NC}"
fi
echo ""

# Optionally upload to S3
if [ "${UPLOAD_TO_S3:-false}" == "true" ]; then
    echo -e "${YELLOW}Uploading to S3...${NC}"
    aws s3 cp "$HTML_FILE" \
        s3://${S3_BUCKET}/${S3_PREFIX}/index.html \
        --content-type "text/html" \
        --region ${AWS_REGION}
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Uploaded to s3://${S3_BUCKET}/${S3_PREFIX}/index.html${NC}"
    else
        echo -e "${RED}Error: Failed to upload to S3${NC}"
        exit 1
    fi
    echo ""
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}HTML Update Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "API URL injected: ${API_GATEWAY_URL}"
echo "HTML file: ${HTML_FILE}"
echo ""
if [ "${UPLOAD_TO_S3:-false}" != "true" ]; then
    echo -e "${YELLOW}To upload to S3, run:${NC}"
    echo "  UPLOAD_TO_S3=true ./inject_api_url_to_html.sh"
    echo "  OR"
    echo "  aws s3 cp ${HTML_FILE} s3://${S3_BUCKET}/${S3_PREFIX}/index.html --content-type 'text/html'"
fi
echo ""
