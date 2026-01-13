#!/bin/bash
# Create IAM role for PHTS Lambda function

set -e

ROLE_NAME="phts-lambda-role"
POLICY_NAME="phts-lambda-policy"

echo "Creating IAM role for Lambda..."

# Trust policy for Lambda (inline JSON)
TRUST_POLICY='{
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
}'

# Create role
if aws iam get-role --role-name ${ROLE_NAME} > /dev/null 2>&1; then
    echo "Role ${ROLE_NAME} already exists"
else
    echo "Creating IAM role: ${ROLE_NAME}"
    echo "${TRUST_POLICY}" > /tmp/trust-policy.json
    aws iam create-role \
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document "${TRUST_POLICY}" \
        --description "IAM role for PHTS Risk Calculator Lambda function"
    echo "✓ Role created"
fi

# Policy document for Lambda permissions (inline JSON)
LAMBDA_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::jerome-dixon.io",
        "arn:aws:s3:::jerome-dixon.io/*"
      ]
    }
  ]
}'

# Attach basic Lambda execution policy
echo "Attaching AWS managed policy: AWSLambdaBasicExecutionRole"
aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || echo "Policy already attached"

# Create and attach custom policy for S3 access
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn ${POLICY_ARN} > /dev/null 2>&1; then
    echo "Policy ${POLICY_NAME} already exists"
else
    echo "Creating IAM policy: ${POLICY_NAME}"
    POLICY_ARN=$(aws iam create-policy \
        --policy-name ${POLICY_NAME} \
        --policy-document "${LAMBDA_POLICY}" \
        --query 'Policy.Arn' \
        --output text)
    echo "✓ Policy created: ${POLICY_ARN}"
fi

# Attach custom policy to role
echo "Attaching custom policy to role..."
aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn ${POLICY_ARN} 2>/dev/null || echo "Policy already attached"

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query 'Role.Arn' --output text)

echo ""
echo "✓ IAM role setup complete"
echo "Role ARN: ${ROLE_ARN}"
echo ""
echo "You can now create the Lambda function with:"
echo "  aws lambda create-function \\"
echo "    --function-name phts-risk-calculator \\"
echo "    --package-type Image \\"
echo "    --code ImageUri=YOUR_ECR_URI \\"
echo "    --role ${ROLE_ARN} \\"
echo "    --timeout 60 \\"
echo "    --memory-size 3008 \\"
echo "    --region us-east-1"
