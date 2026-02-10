# Set up API Gateway for PHTS Lambda function
# Usage: .\setup_api_gateway.ps1

$ErrorActionPreference = "Stop"

# Configuration
$AWS_REGION = if ($env:AWS_REGION) { $env:AWS_REGION } else { "us-east-1" }
$API_NAME = if ($env:API_NAME) { $env:API_NAME } else { "phts-calculator-api" }
$LAMBDA_FUNCTION_NAME = if ($env:LAMBDA_FUNCTION_NAME) { $env:LAMBDA_FUNCTION_NAME } else { "phts-risk-calculator" }
$STAGE_NAME = if ($env:STAGE_NAME) { $env:STAGE_NAME } else { "prod" }

Write-Host "========================================" -ForegroundColor Blue
Write-Host "Setting up API Gateway for PHTS" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

# Step 1: Get Lambda function ARN
Write-Host "Getting Lambda function ARN..." -ForegroundColor Yellow
try {
    $lambdaOut = aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $AWS_REGION --query "Configuration.FunctionArn" --output text 2>&1
    if ($LASTEXITCODE -ne 0) { throw $lambdaOut }
    $LAMBDA_ARN = $lambdaOut.Trim()
} catch {
    Write-Host "Error: Lambda function not found: $LAMBDA_FUNCTION_NAME" -ForegroundColor Red
    exit 1
}
Write-Host "Lambda ARN: $LAMBDA_ARN" -ForegroundColor Green
Write-Host ""

# Step 2: Create or get REST API
Write-Host "Creating/Getting REST API..." -ForegroundColor Yellow
$apiList = aws apigateway get-rest-apis --region $AWS_REGION --output json 2>$null | ConvertFrom-Json
$API_ID = ($apiList.items | Where-Object { $_.name -eq $API_NAME } | Select-Object -First 1).id

if (-not $API_ID) {
    Write-Host "  API not found by name, trying known API ID: 359vxflbzj"
    try {
        aws apigateway get-rest-api --rest-api-id "359vxflbzj" --region $AWS_REGION 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $API_ID = "359vxflbzj"
            Write-Host "Using existing API (by ID): $API_ID" -ForegroundColor Green
        }
    } catch {}
}

if (-not $API_ID) {
    Write-Host "Creating new REST API..."
    $createOut = aws apigateway create-rest-api --name $API_NAME --description "PHTS Risk Calculator API" --region $AWS_REGION --query "id" --output text
    $API_ID = $createOut.Trim()
    Write-Host "Created API: $API_ID" -ForegroundColor Green
} else {
    Write-Host "Using existing API: $API_ID" -ForegroundColor Green
}
Write-Host ""

# Step 3: Get root resource ID
Write-Host "Getting root resource and existing resources..." -ForegroundColor Yellow
$resources = aws apigateway get-resources --rest-api-id $API_ID --region $AWS_REGION --output json | ConvertFrom-Json
$ROOT_RESOURCE_ID = ($resources.items | Where-Object { $_.path -eq "/" } | Select-Object -First 1).id
Write-Host "Root resource: $ROOT_RESOURCE_ID" -ForegroundColor Green

function Get-OrCreateResource {
    param([string]$PathPart)
    $pathFull = "/$PathPart"
    $existing = $resources.items | Where-Object { $_.path -eq $pathFull } | Select-Object -First 1
    if ($existing) {
        return $existing.id
    }
    $createOut = aws apigateway create-resource --rest-api-id $API_ID --parent-id $ROOT_RESOURCE_ID --path-part $PathPart --region $AWS_REGION --query "id" --output text
    # Refresh resources for next call
    $script:resources = aws apigateway get-resources --rest-api-id $API_ID --region $AWS_REGION --output json | ConvertFrom-Json
    return $createOut.Trim()
}

$LAMBDA_INVOKE_URI = "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

# Step 4: Ensure /metadata
Write-Host "Ensuring /metadata resource..." -ForegroundColor Yellow
$METADATA_RESOURCE_ID = Get-OrCreateResource "metadata"
Write-Host "/metadata resource ID: $METADATA_RESOURCE_ID" -ForegroundColor Green
aws apigateway put-method --rest-api-id $API_ID --resource-id $METADATA_RESOURCE_ID --http-method GET --authorization-type NONE --region $AWS_REGION | Out-Null
aws apigateway put-integration --rest-api-id $API_ID --resource-id $METADATA_RESOURCE_ID --http-method GET --type AWS_PROXY --integration-http-method POST --uri $LAMBDA_INVOKE_URI --region $AWS_REGION | Out-Null
Write-Host "Configured GET /metadata" -ForegroundColor Green
Write-Host ""

# Step 4b: Ensure /model-metrics
Write-Host "Ensuring /model-metrics resource..." -ForegroundColor Yellow
$MODEL_METRICS_RESOURCE_ID = Get-OrCreateResource "model-metrics"
Write-Host "/model-metrics resource ID: $MODEL_METRICS_RESOURCE_ID" -ForegroundColor Green
aws apigateway put-method --rest-api-id $API_ID --resource-id $MODEL_METRICS_RESOURCE_ID --http-method GET --authorization-type NONE --region $AWS_REGION | Out-Null
aws apigateway put-integration --rest-api-id $API_ID --resource-id $MODEL_METRICS_RESOURCE_ID --http-method GET --type AWS_PROXY --integration-http-method POST --uri $LAMBDA_INVOKE_URI --region $AWS_REGION | Out-Null
Write-Host "Configured GET /model-metrics" -ForegroundColor Green
Write-Host ""

# Step 5: Ensure /risk
Write-Host "Ensuring /risk resource..." -ForegroundColor Yellow
$RISK_RESOURCE_ID = Get-OrCreateResource "risk"
Write-Host "/risk resource ID: $RISK_RESOURCE_ID" -ForegroundColor Green
aws apigateway put-method --rest-api-id $API_ID --resource-id $RISK_RESOURCE_ID --http-method POST --authorization-type NONE --region $AWS_REGION | Out-Null
aws apigateway put-integration --rest-api-id $API_ID --resource-id $RISK_RESOURCE_ID --http-method POST --type AWS_PROXY --integration-http-method POST --uri $LAMBDA_INVOKE_URI --region $AWS_REGION | Out-Null
Write-Host "Configured POST /risk" -ForegroundColor Green
Write-Host ""

# Step 6: Ensure /causal
Write-Host "Ensuring /causal resource..." -ForegroundColor Yellow
$CAUSAL_RESOURCE_ID = Get-OrCreateResource "causal"
Write-Host "/causal resource ID: $CAUSAL_RESOURCE_ID" -ForegroundColor Green
aws apigateway put-method --rest-api-id $API_ID --resource-id $CAUSAL_RESOURCE_ID --http-method POST --authorization-type NONE --region $AWS_REGION | Out-Null
aws apigateway put-integration --rest-api-id $API_ID --resource-id $CAUSAL_RESOURCE_ID --http-method POST --type AWS_PROXY --integration-http-method POST --uri $LAMBDA_INVOKE_URI --region $AWS_REGION | Out-Null
Write-Host "Configured POST /causal" -ForegroundColor Green
Write-Host ""

# Step 7: CORS (OPTIONS) - route OPTIONS to Lambda so it returns 200 with CORS headers (avoids MOCK 500)
Write-Host "Configuring CORS (OPTIONS -> Lambda)..." -ForegroundColor Yellow
$resourceIds = @($METADATA_RESOURCE_ID, $MODEL_METRICS_RESOURCE_ID, $RISK_RESOURCE_ID, $CAUSAL_RESOURCE_ID)
foreach ($rid in $resourceIds) {
    try { aws apigateway put-method --rest-api-id $API_ID --resource-id $rid --http-method OPTIONS --authorization-type NONE --region $AWS_REGION 2>$null | Out-Null } catch {}
    aws apigateway put-integration --rest-api-id $API_ID --resource-id $rid --http-method OPTIONS --type AWS_PROXY --integration-http-method POST --uri $LAMBDA_INVOKE_URI --region $AWS_REGION 2>$null | Out-Null
}
Write-Host "Configured CORS (OPTIONS to Lambda)" -ForegroundColor Green
Write-Host ""

# Step 8: Lambda permission
Write-Host "Granting API Gateway permission to invoke Lambda..." -ForegroundColor Yellow
$sourceArn = "arn:aws:execute-api:${AWS_REGION}:*:${API_ID}/*/*"
try {
    aws lambda add-permission --function-name $LAMBDA_FUNCTION_NAME --statement-id apigateway-invoke --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn $sourceArn --region $AWS_REGION 2>&1 | Out-Null
} catch {}
Write-Host "Lambda permissions configured" -ForegroundColor Green
Write-Host ""

# Step 9: Deploy
Write-Host "Deploying API to $STAGE_NAME stage..." -ForegroundColor Yellow
aws apigateway create-deployment --rest-api-id $API_ID --stage-name $STAGE_NAME --region $AWS_REGION | Out-Null
Write-Host "API deployed" -ForegroundColor Green
Write-Host ""

# Step 10 & 11: API URL and Lambda env (jq builds Variables JSON, pass directly to aws)
$API_URL = "https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${STAGE_NAME}"
Write-Host "Updating Lambda environment variable with API URL..." -ForegroundColor Yellow
try {
    $envJson = aws lambda get-function-configuration --function-name $LAMBDA_FUNCTION_NAME --region $AWS_REGION --query "Environment.Variables" --output json 2>$null
    if (-not $envJson) { $envJson = "{}" }
    $varsJson = $envJson | jq -c --arg api_url $API_URL --arg bucket "jerome-dixon.io" --arg prefix "uva/phts-risk-calculator" '. + {"API_GATEWAY_URL": $api_url, "PHTS_BUCKET": $bucket, "S3_PREFIX": $prefix}'
    $envArg = "Variables=" + $varsJson
    $awsArgs = @("lambda", "update-function-configuration", "--function-name", $LAMBDA_FUNCTION_NAME, "--environment", $envArg, "--region", $AWS_REGION)
    & aws @awsArgs 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Lambda environment variables updated" -ForegroundColor Green
    } else {
        throw "aws exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "Warning: Could not update Lambda environment variables" -ForegroundColor Yellow
    Write-Host "  You can set API_GATEWAY_URL=$API_URL manually."
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Blue
Write-Host "API Gateway Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""
Write-Host "API ID: $API_ID"
Write-Host "API URL: $API_URL"
Write-Host ""
Write-Host "Endpoints:"
Write-Host "  GET  $API_URL/metadata"
Write-Host "  GET  $API_URL/model-metrics"
Write-Host "  POST $API_URL/risk"
Write-Host "  POST $API_URL/causal"
Write-Host ""
Write-Host "Test: Invoke-RestMethod -Uri '$API_URL/metadata?cohort=Combined' -Method Get" -ForegroundColor Yellow
Write-Host ""
