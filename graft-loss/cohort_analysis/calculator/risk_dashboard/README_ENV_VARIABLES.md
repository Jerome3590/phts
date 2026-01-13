# Lambda Environment Variables Management

## Overview

The PHTS Lambda function uses environment variables to configure:
- API Gateway URL (for frontend communication)
- S3 bucket and prefix (for model/data fallback)
- Other configuration options

## Environment Variables

### Required Variables

- **`API_GATEWAY_URL`**: The API Gateway endpoint URL
  - Format: `https://API_ID.execute-api.REGION.amazonaws.com/STAGE`
  - Used by: Lambda returns this in `/metadata` endpoint for frontend discovery

- **`PHTS_BUCKET`**: S3 bucket name
  - Default: `jerome-dixon.io`
  - Used by: Lambda for S3 fallback (if models not in container)

- **`S3_PREFIX`**: S3 prefix path
  - Default: `uva/phts-risk-calculator`
  - Used by: Lambda for constructing S3 paths

### Optional Variables

- **`MODEL_BASE_PATH`**: Path to models in container
  - Default: `/var/task/models`
  - Used by: Lambda to load models from container filesystem

- **`DASHBOARD_DATA_PATH`**: Path to dashboard data in container
  - Default: `/var/task/dashboard_data`
  - Used by: Lambda to load causal factors data

- **`MODEL_CACHE_TTL`**: Model cache time-to-live (seconds)
  - Default: `3600` (1 hour)
  - Used by: Lambda for in-memory model caching

## Setting Environment Variables

### Method 1: Using update_lambda_env.sh (Recommended)

```bash
# Set API Gateway URL and update Lambda
API_GATEWAY_URL='https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod' \
  ./update_lambda_env.sh
```

The script will:
1. Get current environment variables
2. Merge with new values
3. Update Lambda function
4. Verify the update

### Method 2: Using AWS CLI Directly

```bash
# Get current environment variables
CURRENT_ENV=$(aws lambda get-function-configuration \
    --function-name phts-risk-calculator \
    --query 'Environment.Variables' \
    --output json)

# Merge with new values
NEW_ENV=$(echo "$CURRENT_ENV" | jq '. + {
    "API_GATEWAY_URL": "https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod",
    "PHTS_BUCKET": "jerome-dixon.io",
    "S3_PREFIX": "uva/phts-risk-calculator"
}')

# Update Lambda
aws lambda update-function-configuration \
    --function-name phts-risk-calculator \
    --environment "Variables=$NEW_ENV"
```

### Method 3: During Lambda Creation

```bash
aws lambda create-function \
    --function-name phts-risk-calculator \
    --package-type Image \
    --code ImageUri=YOUR_ECR_URI \
    --environment Variables="{
        \"API_GATEWAY_URL\":\"https://API_ID.execute-api.REGION.amazonaws.com/prod\",
        \"PHTS_BUCKET\":\"jerome-dixon.io\",
        \"S3_PREFIX\":\"uva/phts-risk-calculator\"
    }"
```

## Viewing Environment Variables

```bash
# Get all environment variables
aws lambda get-function-configuration \
    --function-name phts-risk-calculator \
    --query 'Environment.Variables' \
    --output json | jq '.'
```

## Updating HTML with API URL

After setting the Lambda environment variable, inject it into the HTML:

### Method 1: Automatic Injection (Recommended)

```bash
# Inject API URL and upload to S3
API_GATEWAY_URL='https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod' \
  UPLOAD_TO_S3=true \
  ./inject_api_url_to_html.sh
```

### Method 2: Manual Update

1. Get API URL from Lambda:
```bash
API_URL=$(aws lambda get-function-configuration \
    --function-name phts-risk-calculator \
    --query 'Environment.Variables.API_GATEWAY_URL' \
    --output text)
```

2. Update HTML file:
```bash
sed -i "s|const LAMBDA_API_URL = .*;|const LAMBDA_API_URL = '${API_URL}';|g" phts_dashboard.html
```

3. Upload to S3:
```bash
aws s3 cp phts_dashboard.html \
    s3://jerome-dixon.io/uva/phts-risk-calculator/index.html \
    --content-type "text/html"
```

## Dynamic API URL Discovery

The HTML page can also discover the API URL dynamically:

1. **From Lambda Metadata Endpoint**:
   - HTML calls `/metadata` endpoint
   - Lambda returns `api_url` in response
   - HTML uses this URL for subsequent requests

2. **From Window Variable**:
   - Deployment script injects `window.LAMBDA_API_URL`
   - HTML checks this variable on load
   - Falls back to metadata endpoint if not found

## Complete Deployment Workflow

```bash
# 1. Set up API Gateway
./setup_api_gateway.sh
# (This automatically sets Lambda environment variable)

# 2. Inject API URL into HTML and upload
API_GATEWAY_URL='https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod' \
  UPLOAD_TO_S3=true \
  ./inject_api_url_to_html.sh

# 3. Verify
curl 'https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod/metadata?cohort=Combined'
```

## Troubleshooting

### Environment Variable Not Set

**Symptom**: Lambda returns `null` for `api_url` in metadata

**Fix**:
```bash
./update_lambda_env.sh
```

### HTML Can't Find API URL

**Symptom**: Browser console shows "API URL not found"

**Fix**:
1. Check Lambda environment variable is set
2. Verify API Gateway is deployed
3. Update HTML with correct URL

### CORS Errors

**Symptom**: Browser shows CORS error

**Fix**:
1. Verify Lambda returns CORS headers
2. Check API Gateway CORS configuration
3. Ensure OPTIONS method is configured

## Best Practices

1. **Use Environment Variables**: Don't hardcode URLs in code
2. **Version Control**: Keep environment variable values in deployment scripts
3. **Separate Environments**: Use different API Gateway stages (dev, prod)
4. **Automate**: Use scripts to update environment variables
5. **Verify**: Always verify environment variables after update
