#!/bin/bash
# Deploy PHTS Risk Calculator Dashboard to S3 and Lambda

set -e

# Configuration
BUCKET_NAME="${PHTS_BUCKET:-jerome-dixon.io}"
S3_PREFIX="${S3_PREFIX:-uva/phts-risk-calculator}"
LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-phts-risk-calculator}"
REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-phts-dashboard}"

echo "Deploying PHTS Risk Calculator Dashboard..."
echo "Bucket: $BUCKET_NAME"
echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "Region: $REGION"

# Step 1: Create S3 bucket if it doesn't exist
echo "Creating S3 bucket..."
aws s3 mb s3://$BUCKET_NAME --region $REGION 2>/dev/null || echo "Bucket already exists"

# Step 2: Upload dashboard HTML
echo "Uploading dashboard HTML..."
aws s3 cp phts_dashboard.html s3://$BUCKET_NAME/$S3_PREFIX/index.html \
    --content-type "text/html" \
    --region $REGION

# Step 3: Configure S3 bucket for static website hosting
echo "Configuring S3 bucket for static website hosting..."
# Note: If bucket already has website hosting configured, this may need to be done via console
# or with proper index/error document paths
aws s3 website s3://$BUCKET_NAME \
    --index-document uva/phts-risk-calculator/index.html \
    --error-document uva/phts-risk-calculator/index.html \
    --region $REGION 2>/dev/null || echo "Website hosting may need manual configuration"

# Step 4: Set bucket policy for public read access
echo "Setting bucket policy for public read access..."
cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET_NAME/$S3_PREFIX/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy \
    --bucket $BUCKET_NAME \
    --policy file:///tmp/bucket-policy.json \
    --region $REGION

# Step 5: Upload models and dashboard data to S3
echo "Uploading models and dashboard data to S3..."
MODELS_DIR="../outputs/models"
DASHBOARD_DIR="../outputs/shap_ffa"

if [ -d "$MODELS_DIR" ]; then
    echo "Uploading models..."
    aws s3 sync $MODELS_DIR s3://$BUCKET_NAME/$S3_PREFIX/models/ \
        --region $REGION
fi

if [ -d "$DASHBOARD_DIR" ]; then
    echo "Uploading dashboard data..."
    aws s3 sync $DASHBOARD_DIR s3://$BUCKET_NAME/$S3_PREFIX/dashboard_data/ \
        --region $REGION
fi

# Step 6: Package Lambda function
echo "Packaging Lambda function..."
mkdir -p /tmp/lambda-package
cp phts_lambda_function.py /tmp/lambda-package/
cd /tmp/lambda-package

# Install dependencies (if using Lambda Layers, skip this)
# pip install -r ../phts_requirements.txt -t . --upgrade

# Create deployment package
zip -r /tmp/lambda-deployment.zip . -x "*.pyc" "__pycache__/*" "*.dist-info/*"

# Step 7: Create/Update Lambda function
echo "Creating/updating Lambda function..."
cd -

# Check if function exists
if aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $REGION &>/dev/null; then
    echo "Updating existing Lambda function..."
    aws lambda update-function-code \
        --function-name $LAMBDA_FUNCTION_NAME \
        --zip-file fileb:///tmp/lambda-deployment.zip \
        --region $REGION
else
    echo "Creating new Lambda function..."
    # Create IAM role for Lambda (if needed)
    ROLE_ARN=$(aws iam get-role --role-name phts-lambda-role --query 'Role.Arn' --output text 2>/dev/null || echo "")
    
    if [ -z "$ROLE_ARN" ]; then
        echo "Creating IAM role for Lambda..."
        cat > /tmp/lambda-role-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        aws iam create-role \
            --role-name phts-lambda-role \
            --assume-role-policy-document file:///tmp/lambda-role-policy.json \
            --region $REGION
        
        # Attach basic Lambda execution policy
        aws iam attach-role-policy \
            --role-name phts-lambda-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            --region $REGION
        
        # Attach S3 read policy
        cat > /tmp/s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::$BUCKET_NAME/$S3_PREFIX/*",
        "arn:aws:s3:::$BUCKET_NAME/$S3_PREFIX"
      ]
    }
  ]
}
EOF
        
        aws iam put-role-policy \
            --role-name phts-lambda-role \
            --policy-name S3ReadAccess \
            --policy-document file:///tmp/s3-policy.json \
            --region $REGION
        
        ROLE_ARN=$(aws iam get-role --role-name phts-lambda-role --query 'Role.Arn' --output text --region $REGION)
        
        # Wait for role to be ready
        sleep 5
    fi
    
    aws lambda create-function \
        --function-name $LAMBDA_FUNCTION_NAME \
        --runtime python3.11 \
        --role $ROLE_ARN \
        --handler phts_lambda_function.lambda_handler \
        --zip-file fileb:///tmp/lambda-deployment.zip \
        --timeout 60 \
        --memory-size 3008 \
        --environment Variables="{PHTS_BUCKET=$BUCKET_NAME,S3_PREFIX=$S3_PREFIX}" \
        --region $REGION
fi

# Step 8: Create API Gateway (optional - can use Lambda Function URL instead)
echo "Dashboard deployment complete!"
echo ""
echo "Dashboard URL:"
echo "  - S3 Path: s3://$BUCKET_NAME/$S3_PREFIX/"
echo "  - If website hosting enabled: http://$BUCKET_NAME.s3-website-$REGION.amazonaws.com/$S3_PREFIX/"
echo ""
echo "Next steps:"
echo "1. Update LAMBDA_API_URL in phts_dashboard.html with your API endpoint"
echo "2. Re-upload updated HTML: aws s3 cp phts_dashboard.html s3://$BUCKET_NAME/$S3_PREFIX/index.html"
echo "3. Configure CloudFront distribution for HTTPS (recommended)"
echo "4. Set up custom domain if needed (jerome-dixon.io/uva/phts-risk-calculator)"
