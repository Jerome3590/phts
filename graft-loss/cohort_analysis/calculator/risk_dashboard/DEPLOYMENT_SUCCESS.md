# PHTS Dashboard Deployment - Success! ✅

## Deployment Summary

All components have been successfully deployed!

### ✅ Completed Steps

1. **Models and Data Prepared** - Copied to `lambda_dir_phts/`
2. **Docker Image Built** - Fixed XGBoost/NumPy compilation issues
3. **Docker Image Format Fixed** - Updated build script to use Docker format (not OCI) for Lambda compatibility
4. **Docker Image Pushed to ECR** - `535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest`
5. **IAM Role Created** - `phts-lambda-role` with necessary permissions
6. **Lambda Function Created** - `phts-risk-calculator` (Status: **Active** ✅)
7. **API Gateway Configured** - REST API with endpoints:
   - `GET /metadata`
   - `POST /risk`
   - `POST /causal`
   - API URL: `https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod`
8. **Environment Variables Set** - Including API Gateway URL
9. **HTML Uploaded to S3** - `s3://jerome-dixon.io/uva/phts-risk-calculator/index.html`

## Key Fix Applied

### Docker Image Format Issue

**Problem**: Lambda was rejecting the image with error: `InvalidImage - UnsupportedImageLayerDetected`

**Solution**: Updated `docker_build_phts.sh` to build in Docker format instead of OCI format:

```bash
# Use DOCKER_BUILDKIT=0 to ensure Docker format
DOCKER_BUILDKIT=0 docker build -f Dockerfile.phts -t ${ECR_REPOSITORY}:${IMAGE_TAG} .
```

This ensures the image is in Docker format, which Lambda requires.

## Deployment URLs

- **Dashboard**: `https://jerome-dixon.io/uva/phts-risk-calculator/`
- **API Gateway**: `https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod`
- **Lambda Function**: `phts-risk-calculator` (us-east-1)
- **ECR Image**: `535362115856.dkr.ecr.us-east-1.amazonaws.com/phts-risk-calculator:latest`

## Next Steps

1. **Test the Dashboard**: Open `https://jerome-dixon.io/uva/phts-risk-calculator/` in a browser
2. **Test API Endpoints**:
   ```bash
   # Test metadata endpoint
   curl "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata?cohort=Combined"
   
   # Test risk calculation
   curl -X POST "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/risk" \
     -H "Content-Type: application/json" \
     -d '{"cohort":"Combined","features":{"egfr_tx":60.0}}'
   ```

3. **Monitor Lambda Logs**:
   ```bash
   aws logs tail /aws/lambda/phts-risk-calculator --follow
   ```

## Troubleshooting

If you encounter issues:

1. **Check Lambda Status**:
   ```bash
   aws lambda get-function --function-name phts-risk-calculator --region us-east-1
   ```

2. **Check API Gateway**:
   ```bash
   aws apigateway get-rest-apis --query "items[?name=='phts-calculator-api']"
   ```

3. **View Lambda Logs**:
   ```bash
   aws logs tail /aws/lambda/phts-risk-calculator --follow
   ```

## Deployment Scripts

All deployment scripts are in `graft-loss/cohort_analysis/calculator/risk_dashboard/`:

- `prepare_lambda_dir_phts.py` - Prepares models and data
- `docker_build_phts.sh` - Builds and pushes Docker image (now with Docker format)
- `create_lambda_role.sh` - Creates IAM role
- `setup_api_gateway.sh` - Sets up API Gateway
- `update_lambda_env.sh` - Updates environment variables
- `inject_api_url_to_html.sh` - Injects API URL into HTML
- `deploy_complete.sh` - Complete automated deployment

## Notes

- The Docker build script now uses `DOCKER_BUILDKIT=0` to ensure Docker format compatibility with Lambda
- Lambda function is configured with 3008 MB memory and 60 second timeout
- Models are included in the container image (2.46 GB total)
- Dashboard data (causal factors) is included in the container

---

**Deployment Date**: $(date)
**Status**: ✅ Complete and Active
