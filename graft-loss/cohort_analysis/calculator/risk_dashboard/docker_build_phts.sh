#!/bin/bash
# Build and push PHTS Lambda container image to ECR

set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
ECR_REPOSITORY=${ECR_REPOSITORY:-phts-risk-calculator}
IMAGE_TAG=${IMAGE_TAG:-latest}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PHTS Lambda Container Build & Deploy${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Prepare lambda_dir_phts (if not already done)
if [ ! -d "lambda_dir_phts/models" ]; then
    echo -e "${YELLOW}Preparing lambda directory...${NC}"
    python prepare_lambda_dir_phts.py
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to prepare lambda directory${NC}"
        exit 1
    fi
    echo ""
else
    echo -e "${GREEN}✓ Lambda directory already prepared${NC}"
    echo ""
fi

# Step 2: Validate lambda directory
echo -e "${YELLOW}Validating lambda directory...${NC}"
if [ ! -d "lambda_dir_phts/models" ] || [ ! -d "lambda_dir_phts/dashboard_data" ]; then
    echo -e "${RED}Error: lambda_dir_phts structure is invalid${NC}"
    exit 1
fi

# Check for at least one cohort's models
MODEL_COUNT=$(find lambda_dir_phts/models -name "*.cbm" -o -name "*.ubj" | wc -l)
if [ $MODEL_COUNT -eq 0 ]; then
    echo -e "${RED}Error: No model files found in lambda_dir_phts/models${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found $MODEL_COUNT model files${NC}"
echo ""

# Step 3: Check Docker permissions
echo -e "${YELLOW}Checking Docker permissions...${NC}"
if ! docker ps &>/dev/null; then
    echo -e "${RED}Error: Cannot access Docker daemon${NC}"
    echo ""
    echo "This usually means:"
    echo "  1. Docker service is not running, OR"
    echo "  2. Your user is not in the docker group"
    echo ""
    echo "To fix:"
    echo "  # Add your user to docker group:"
    echo "  sudo usermod -aG docker \$USER"
    echo ""
    echo "  # Then either:"
    echo "  #   - Log out and log back in, OR"
    echo "  #   - Run: newgrp docker"
    echo ""
    echo "  # Or use the helper script:"
    echo "  bash fix_docker_permissions.sh"
    echo ""
    echo "After fixing, verify with: docker ps"
    exit 1
fi
echo -e "${GREEN}✓ Docker access verified${NC}"
echo ""

# Step 4: Build Docker image
# Use buildx with --load to build and load into local Docker (Docker format for Lambda)
echo -e "${YELLOW}Building Docker image...${NC}"
docker buildx build --load --platform linux/amd64 -f Dockerfile.phts -t ${ECR_REPOSITORY}:${IMAGE_TAG} .
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Docker build failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker image built successfully${NC}"
echo ""

# Step 5: Get ECR login token
echo -e "${YELLOW}Logging in to ECR...${NC}"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY}
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: ECR login failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Logged in to ECR${NC}"
echo ""

# Step 6: Create ECR repository if it doesn't exist
echo -e "${YELLOW}Checking ECR repository...${NC}"
if aws ecr describe-repositories --repository-names ${ECR_REPOSITORY} --region ${AWS_REGION} &>/dev/null; then
    echo -e "${GREEN}✓ ECR repository exists: ${ECR_REPOSITORY}${NC}"
else
    echo -e "${YELLOW}Creating ECR repository...${NC}"
    aws ecr create-repository \
        --repository-name ${ECR_REPOSITORY} \
        --region ${AWS_REGION} \
        --image-scanning-configuration scanOnPush=true \
        --image-tag-mutability MUTABLE
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create ECR repository${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ ECR repository created${NC}"
fi
echo ""

# Step 7: Tag image for ECR
ECR_URI=${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
echo -e "${YELLOW}Tagging image...${NC}"
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${ECR_URI}
echo -e "${GREEN}✓ Image tagged: ${ECR_URI}${NC}"
echo ""

# Step 8: Push to ECR
echo -e "${YELLOW}Pushing image to ECR (this may take a while)...${NC}"
docker push ${ECR_URI}
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Docker push failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Image pushed successfully${NC}"
echo ""

# Step 9: Get image size
IMAGE_SIZE=$(docker images ${ECR_REPOSITORY}:${IMAGE_TAG} --format "{{.Size}}")
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "ECR Image URI: ${ECR_URI}"
echo "Image Size: ${IMAGE_SIZE}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Update Lambda function to use container image:"
echo "   aws lambda update-function-code \\"
echo "     --function-name phts-risk-calculator \\"
echo "     --image-uri ${ECR_URI} \\"
echo "     --region ${AWS_REGION}"
echo ""
echo "2. Or create new Lambda function:"
echo "   aws lambda create-function \\"
echo "     --function-name phts-risk-calculator \\"
echo "     --package-type Image \\"
echo "     --code ImageUri=${ECR_URI} \\"
echo "     --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/phts-lambda-role \\"
echo "     --timeout 60 \\"
echo "     --memory-size 3008 \\"
echo "     --region ${AWS_REGION}"
echo ""
echo "3. Set environment variables:"
echo "   aws lambda update-function-configuration \\"
echo "     --function-name phts-risk-calculator \\"
echo "     --environment Variables={PHTS_BUCKET=jerome-dixon.io,S3_PREFIX=uva/phts-risk-calculator} \\"
echo "     --region ${AWS_REGION}"
echo ""
