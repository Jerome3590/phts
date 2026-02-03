#!/bin/bash
# Complete PHTS Dashboard Deployment Workflow

set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME:-phts-risk-calculator}
S3_BUCKET=${S3_BUCKET:-jerome-dixon.io}
S3_PREFIX=${S3_PREFIX:-uva/phts-risk-calculator}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PHTS Dashboard Complete Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Prepare models and data
echo -e "${YELLOW}[1/7] Preparing models and data...${NC}"
if ! python prepare_lambda_dir_phts.py; then
    echo -e "${RED}Error: Failed to prepare lambda directory${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Models and data prepared${NC}"
echo ""

# Step 2: Build and push Docker image
echo -e "${YELLOW}[2/7] Building and pushing Docker image to ECR...${NC}"
if ! ./docker_build_phts.sh; then
    echo -e "${RED}Error: Docker build/push failed${NC}"
    exit 1
fi

# Get ECR URI
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/phts-risk-calculator:latest"
echo -e "${GREEN}✓ Docker image pushed: ${ECR_URI}${NC}"
echo ""

# Step 3: Update Lambda function
echo -e "${YELLOW}[3/7] Updating Lambda function...${NC}"
if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo "Updating existing Lambda function..."
    aws lambda update-function-code \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --image-uri ${ECR_URI} \
        --region ${AWS_REGION} > /dev/null
    
    echo "Waiting for Lambda update to complete..."
    aws lambda wait function-updated \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --region ${AWS_REGION}
    echo -e "${GREEN}✓ Lambda function updated${NC}"
else
    echo -e "${YELLOW}⚠ Lambda function not found. Please create it first:${NC}"
    echo "   aws lambda create-function \\"
    echo "     --function-name ${LAMBDA_FUNCTION_NAME} \\"
    echo "     --package-type Image \\"
    echo "     --code ImageUri=${ECR_URI} \\"
    echo "     --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/phts-lambda-role \\"
    echo "     --timeout 60 \\"
    echo "     --memory-size 3008 \\"
    echo "     --region ${AWS_REGION}"
    exit 1
fi
echo ""

# Step 4: Set up API Gateway
echo -e "${YELLOW}[4/7] Setting up API Gateway...${NC}"
if ! ./setup_api_gateway.sh; then
    echo -e "${RED}Error: API Gateway setup failed${NC}"
    exit 1
fi

# Get API URL - try by name first, then by known ID
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

if [ -z "$API_ID" ]; then
    echo -e "${RED}Error: Could not get API Gateway ID${NC}"
    exit 1
fi

API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
echo -e "${GREEN}✓ API Gateway configured: ${API_URL}${NC}"
echo ""

# Step 5: Update Lambda environment variables (ensure API URL is set)
echo -e "${YELLOW}[5/7] Verifying Lambda environment variables...${NC}"
API_GATEWAY_URL="${API_URL}" ./update_lambda_env.sh
echo ""

# Step 6: Inject API URL into HTML
echo -e "${YELLOW}[6/7] Injecting API URL into HTML...${NC}"
if ! API_GATEWAY_URL="${API_URL}" ./inject_api_url_to_html.sh; then
    echo -e "${RED}Error: Failed to inject API URL${NC}"
    exit 1
fi
echo -e "${GREEN}✓ API URL injected into HTML${NC}"
echo ""

# Step 7: Upload HTML to S3
echo -e "${YELLOW}[7/7] Uploading HTML to S3...${NC}"
if ! aws s3 cp phts_dashboard.html \
    s3://${S3_BUCKET}/${S3_PREFIX}/index.html \
    --content-type "text/html" \
    --region ${AWS_REGION}; then
    echo -e "${RED}Error: Failed to upload HTML to S3${NC}"
    exit 1
fi
if ! aws s3 cp phts_readme.html \
    s3://${S3_BUCKET}/${S3_PREFIX}/phts_readme.html \
    --content-type "text/html" \
    --region ${AWS_REGION}; then
    echo -e "${YELLOW}Warning: Failed to upload Documentation (phts_readme.html) to S3${NC}"
else
    echo -e "${GREEN}✓ Dashboard and Documentation uploaded to S3${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Components Deployed:"
echo "  ✓ Lambda Function: ${LAMBDA_FUNCTION_NAME}"
echo "  ✓ ECR Image: ${ECR_URI}"
echo "  ✓ API Gateway: ${API_URL}"
echo "  ✓ S3 Dashboard: s3://${S3_BUCKET}/${S3_PREFIX}/index.html"
echo "  ✓ S3 Documentation: s3://${S3_BUCKET}/${S3_PREFIX}/phts_readme.html"
echo ""
echo "Dashboard URL:"
echo "  https://${S3_BUCKET}/${S3_PREFIX}/"
echo ""
echo "API Endpoints:"
echo "  GET  ${API_URL}/metadata"
echo "  POST ${API_URL}/risk"
echo "  POST ${API_URL}/causal"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Test API: curl '${API_URL}/metadata?cohort=Combined'"
echo "2. Open dashboard in browser"
echo "3. Test risk calculation"
echo ""
