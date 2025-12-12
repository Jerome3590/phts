#!/bin/bash
# Deployment script for Cohort Risk Dashboard

set -e

# Configuration
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_NAME="graft-loss-cohort-dashboard"
FUNCTION_NAME="graft-loss-cohort-dashboard"
MODELS_BUCKET="uva-graft-loss-cohort-models"
DASHBOARD_BUCKET="uva-graft-loss-cohort-dashboard"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting deployment...${NC}"

# Step 1: Build Docker image
echo -e "${YELLOW}Step 1: Building Docker image...${NC}"
cd lambda/
docker build -t ${REPO_NAME}:latest .
cd ..

# Step 2: Get ECR repository URI
echo -e "${YELLOW}Step 2: Getting ECR repository URI...${NC}"
REPO_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

# Check if repository exists
if ! aws ecr describe-repositories --repository-names ${REPO_NAME} --region ${REGION} &>/dev/null; then
    echo -e "${YELLOW}Creating ECR repository...${NC}"
    aws ecr create-repository \
        --repository-name ${REPO_NAME} \
        --region ${REGION} \
        --image-scanning-configuration scanOnPush=true
fi

# Step 3: Login to ECR
echo -e "${YELLOW}Step 3: Logging in to ECR...${NC}"
aws ecr get-login-password --region ${REGION} | \
    docker login --username AWS --password-stdin ${REPO_URI}

# Step 4: Tag and push image
echo -e "${YELLOW}Step 4: Tagging and pushing image...${NC}"
docker tag ${REPO_NAME}:latest ${REPO_URI}:latest
docker push ${REPO_URI}:latest

# Step 5: Update Lambda function
echo -e "${YELLOW}Step 5: Updating Lambda function...${NC}"
if aws lambda get-function --function-name ${FUNCTION_NAME} --region ${REGION} &>/dev/null; then
    # Update existing function
    aws lambda update-function-code \
        --function-name ${FUNCTION_NAME} \
        --image-uri ${REPO_URI}:latest \
        --region ${REGION} > /dev/null
    
    echo -e "${GREEN}Lambda function updated${NC}"
else
    echo -e "${RED}Lambda function ${FUNCTION_NAME} does not exist. Please create it first.${NC}"
    echo -e "${YELLOW}Use the deployment guide to create the function:${NC}"
    echo "  docs/README_dashboard_deployment.md"
    exit 1
fi

# Step 6: Wait for update to complete
echo -e "${YELLOW}Step 6: Waiting for Lambda update to complete...${NC}"
aws lambda wait function-updated \
    --function-name ${FUNCTION_NAME} \
    --region ${REGION}

# Step 7: Deploy frontend to S3
echo -e "${YELLOW}Step 7: Deploying frontend to S3...${NC}"
aws s3 sync frontend/ s3://${DASHBOARD_BUCKET}/ \
    --exclude "*.git/*" \
    --exclude "node_modules/*" \
    --delete

# Step 8: Get API Gateway URL
echo -e "${YELLOW}Step 8: Getting API Gateway URL...${NC}"
API_ID=$(aws apigateway get-rest-apis \
    --query "items[?name=='graft-loss-cohort-api'].id" \
    --output text \
    --region ${REGION})

if [ -n "$API_ID" ]; then
    API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/prod"
    echo -e "${GREEN}API Gateway URL: ${API_URL}${NC}"
    echo -e "${YELLOW}Update config.js with this URL:${NC}"
    echo "  API_URL: '${API_URL}'"
else
    echo -e "${YELLOW}API Gateway not found. Please create it using the deployment guide.${NC}"
fi

echo -e "${GREEN}Deployment complete!${NC}"

