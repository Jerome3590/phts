#!/bin/bash
# Set up API Gateway for PHTS Lambda function

set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
API_NAME=${API_NAME:-phts-calculator-api}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME:-phts-risk-calculator}
STAGE_NAME=${STAGE_NAME:-prod}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setting up API Gateway for PHTS${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Get Lambda function ARN
echo -e "${YELLOW}Getting Lambda function ARN...${NC}"
LAMBDA_ARN=$(aws lambda get-function \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --region ${AWS_REGION} \
    --query 'Configuration.FunctionArn' \
    --output text)

if [ -z "$LAMBDA_ARN" ]; then
    echo "Error: Lambda function not found: ${LAMBDA_FUNCTION_NAME}"
    exit 1
fi

echo -e "${GREEN}✓ Lambda ARN: ${LAMBDA_ARN}${NC}"
echo ""

# Step 2: Create or get REST API
echo -e "${YELLOW}Creating/Getting REST API...${NC}"
API_ID=$(aws apigateway get-rest-apis \
    --region ${AWS_REGION} \
    --query "items[?name=='${API_NAME}'].id" \
    --output text 2>/dev/null || echo "")

# If not found by name, try known API ID (359vxflbzj)
if [ -z "$API_ID" ]; then
    echo "  API not found by name, trying known API ID: 359vxflbzj"
    KNOWN_API_ID="359vxflbzj"
    if aws apigateway get-rest-api --rest-api-id ${KNOWN_API_ID} --region ${AWS_REGION} &>/dev/null; then
        API_ID=${KNOWN_API_ID}
        echo -e "${GREEN}✓ Using existing API (by ID): ${API_ID}${NC}"
    fi
fi

if [ -z "$API_ID" ]; then
    echo "Creating new REST API..."
    API_ID=$(aws apigateway create-rest-api \
        --name ${API_NAME} \
        --description "PHTS Risk Calculator API" \
        --region ${AWS_REGION} \
        --query 'id' \
        --output text)
    echo -e "${GREEN}✓ Created API: ${API_ID}${NC}"
else
    echo -e "${GREEN}✓ Using existing API: ${API_ID}${NC}"
fi
echo ""

# Step 3: Get root resource ID and existing resources
echo -e "${YELLOW}Getting root resource and existing resources...${NC}"
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id ${API_ID} \
    --region ${AWS_REGION} \
    --query 'items[?path==`/`].id' \
    --output text)
echo -e "${GREEN}✓ Root resource: ${ROOT_RESOURCE_ID}${NC}"

# Get-or-create resource by path (idempotent; uses AWS CLI query only, no jq)
get_or_create_resource() {
    local PATH_PART="$1"
    local PATH_FULL="/${PATH_PART}"
    local EXISTING_ID
    EXISTING_ID=$(aws apigateway get-resources \
        --rest-api-id ${API_ID} \
        --region ${AWS_REGION} \
        --query "items[?path=='${PATH_FULL}'].id" \
        --output text 2>/dev/null)
    if [ -n "$EXISTING_ID" ]; then
        echo "$EXISTING_ID"
        return
    fi
    aws apigateway create-resource \
        --rest-api-id ${API_ID} \
        --parent-id ${ROOT_RESOURCE_ID} \
        --path-part "${PATH_PART}" \
        --region ${AWS_REGION} \
        --query 'id' \
        --output text
}

# Step 4: Ensure /metadata resource and GET method
echo -e "${YELLOW}Ensuring /metadata resource...${NC}"
METADATA_RESOURCE_ID=$(get_or_create_resource "metadata")
echo -e "${GREEN}✓ /metadata resource ID: ${METADATA_RESOURCE_ID}${NC}"
aws apigateway put-method \
    --rest-api-id ${API_ID} \
    --resource-id ${METADATA_RESOURCE_ID} \
    --http-method GET \
    --authorization-type NONE \
    --region ${AWS_REGION} > /dev/null
aws apigateway put-integration \
    --rest-api-id ${API_ID} \
    --resource-id ${METADATA_RESOURCE_ID} \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
    --region ${AWS_REGION} > /dev/null
echo -e "${GREEN}✓ Configured GET /metadata${NC}"
echo ""

# Step 4b: Ensure /model-metrics resource and GET method
echo -e "${YELLOW}Ensuring /model-metrics resource...${NC}"
MODEL_METRICS_RESOURCE_ID=$(get_or_create_resource "model-metrics")
echo -e "${GREEN}✓ /model-metrics resource ID: ${MODEL_METRICS_RESOURCE_ID}${NC}"
aws apigateway put-method \
    --rest-api-id ${API_ID} \
    --resource-id ${MODEL_METRICS_RESOURCE_ID} \
    --http-method GET \
    --authorization-type NONE \
    --region ${AWS_REGION} > /dev/null
aws apigateway put-integration \
    --rest-api-id ${API_ID} \
    --resource-id ${MODEL_METRICS_RESOURCE_ID} \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
    --region ${AWS_REGION} > /dev/null
echo -e "${GREEN}✓ Configured GET /model-metrics${NC}"
echo ""

# Step 5: Ensure /risk resource and POST method
echo -e "${YELLOW}Ensuring /risk resource...${NC}"
RISK_RESOURCE_ID=$(get_or_create_resource "risk")
echo -e "${GREEN}✓ /risk resource ID: ${RISK_RESOURCE_ID}${NC}"
aws apigateway put-method \
    --rest-api-id ${API_ID} \
    --resource-id ${RISK_RESOURCE_ID} \
    --http-method POST \
    --authorization-type NONE \
    --region ${AWS_REGION} > /dev/null
aws apigateway put-integration \
    --rest-api-id ${API_ID} \
    --resource-id ${RISK_RESOURCE_ID} \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
    --region ${AWS_REGION} > /dev/null
echo -e "${GREEN}✓ Configured POST /risk${NC}"
echo ""

# Step 6: Ensure /causal resource and POST method
echo -e "${YELLOW}Ensuring /causal resource...${NC}"
CAUSAL_RESOURCE_ID=$(get_or_create_resource "causal")
echo -e "${GREEN}✓ /causal resource ID: ${CAUSAL_RESOURCE_ID}${NC}"
aws apigateway put-method \
    --rest-api-id ${API_ID} \
    --resource-id ${CAUSAL_RESOURCE_ID} \
    --http-method POST \
    --authorization-type NONE \
    --region ${AWS_REGION} > /dev/null
aws apigateway put-integration \
    --rest-api-id ${API_ID} \
    --resource-id ${CAUSAL_RESOURCE_ID} \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
    --region ${AWS_REGION} > /dev/null
echo -e "${GREEN}✓ Configured POST /causal${NC}"
echo ""

# Step 7: Add OPTIONS methods for CORS
echo -e "${YELLOW}Configuring CORS (OPTIONS methods)...${NC}"

for RESOURCE_ID in ${METADATA_RESOURCE_ID} ${MODEL_METRICS_RESOURCE_ID} ${RISK_RESOURCE_ID} ${CAUSAL_RESOURCE_ID}; do
    aws apigateway put-method \
        --rest-api-id ${API_ID} \
        --resource-id ${RESOURCE_ID} \
        --http-method OPTIONS \
        --authorization-type NONE \
        --region ${AWS_REGION} > /dev/null
    
    aws apigateway put-integration \
        --rest-api-id ${API_ID} \
        --resource-id ${RESOURCE_ID} \
        --http-method OPTIONS \
        --type MOCK \
        --integration-http-method OPTIONS \
        --request-templates '{"application/json":"{\"statusCode\":200}"}' \
        --region ${AWS_REGION} > /dev/null
    
    aws apigateway put-method-response \
        --rest-api-id ${API_ID} \
        --resource-id ${RESOURCE_ID} \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Headers":true,"method.response.header.Access-Control-Allow-Methods":true,"method.response.header.Access-Control-Allow-Origin":true}' \
        --region ${AWS_REGION} > /dev/null
    
    aws apigateway put-integration-response \
        --rest-api-id ${API_ID} \
        --resource-id ${RESOURCE_ID} \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Headers":"'"'"'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"'"'","method.response.header.Access-Control-Allow-Methods":"'"'"'GET,POST,OPTIONS'"'"'","method.response.header.Access-Control-Allow-Origin":"'"'"'*'"'"'"}' \
        --region ${AWS_REGION} > /dev/null
done

echo -e "${GREEN}✓ Configured CORS${NC}"
echo ""

# Step 8: Grant API Gateway permission to invoke Lambda
echo -e "${YELLOW}Granting API Gateway permission to invoke Lambda...${NC}"
aws lambda add-permission \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --statement-id apigateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${AWS_REGION}:*:${API_ID}/*/*" \
    --region ${AWS_REGION} 2>/dev/null || echo "Permission already exists"
echo -e "${GREEN}✓ Lambda permissions configured${NC}"
echo ""

# Step 9: Deploy API
echo -e "${YELLOW}Deploying API to ${STAGE_NAME} stage...${NC}"
aws apigateway create-deployment \
    --rest-api-id ${API_ID} \
    --stage-name ${STAGE_NAME} \
    --region ${AWS_REGION} > /dev/null
echo -e "${GREEN}✓ API deployed${NC}"
echo ""

# Step 10: Get API endpoint URL
API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${STAGE_NAME}"

# Step 11: Update Lambda environment variable with API URL
echo -e "${YELLOW}Updating Lambda environment variable with API URL...${NC}"
CURRENT_ENV=$(aws lambda get-function-configuration \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --region ${AWS_REGION} \
    --query 'Environment.Variables' \
    --output json 2>/dev/null || echo "{}")

ENV_VARS=$(echo "$CURRENT_ENV" | jq -r --arg api_url "$API_URL" \
    --arg bucket "jerome-dixon.io" \
    --arg prefix "uva/phts-risk-calculator" \
    '. + {
        "API_GATEWAY_URL": $api_url,
        "PHTS_BUCKET": $bucket,
        "S3_PREFIX": $prefix
    }')

aws lambda update-function-configuration \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --environment "Variables=$ENV_VARS" \
    --region ${AWS_REGION} > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Lambda environment variables updated${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Could not update Lambda environment variables${NC}"
    echo "   You can update manually with:"
    echo "   API_GATEWAY_URL='${API_URL}' ./update_lambda_env.sh"
fi
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}API Gateway Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "API ID: ${API_ID}"
echo "API URL: ${API_URL}"
echo ""
echo "Endpoints:"
echo "  GET  ${API_URL}/metadata"
echo "  GET  ${API_URL}/model-metrics"
echo "  POST ${API_URL}/risk"
echo "  POST ${API_URL}/causal"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Inject API URL into HTML and upload to S3:"
echo "   API_GATEWAY_URL='${API_URL}' UPLOAD_TO_S3=true ./inject_api_url_to_html.sh"
echo ""
echo "   OR manually:"
echo "   - Update LAMBDA_API_URL in phts_dashboard.html"
echo "   - Upload: aws s3 cp phts_dashboard.html \\"
echo "             s3://jerome-dixon.io/uva/phts-risk-calculator/index.html \\"
echo "             --content-type 'text/html'"
echo ""
echo "2. Test the API:"
echo "   curl '${API_URL}/metadata?cohort=Combined'"
echo ""
