# API Gateway Deployment Status

## Current Status

✅ **API Gateway Created**: `phts-calculator-api` (ID: `359vxflbzj`)
✅ **Resources Configured**:
   - `/metadata` - GET method
   - `/risk` - POST method
   - `/causal` - POST method
   - All have OPTIONS for CORS

✅ **Lambda Integration**: AWS_PROXY integration configured
✅ **Deployed to Stage**: `prod`
✅ **Latest Deployment**: `x1a7hn` (2026-01-13T03:35:51)

## API Endpoint

- **URL**: `https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod`
- **Metadata**: `GET /prod/metadata`
- **Risk**: `POST /prod/risk`
- **Causal**: `POST /prod/causal`

## Lambda Integration

- **Type**: AWS_PROXY
- **Function**: `phts-risk-calculator`
- **Integration Method**: POST
- **Status**: ✅ Configured

## Current Issue

The API Gateway is working correctly and routing requests to Lambda. However, Lambda is returning 500 errors. This means:

1. ✅ API Gateway is deployed and accessible
2. ✅ Requests are reaching Lambda
3. ❌ Lambda function is failing (500 error)

## Next Steps

The Lambda function needs debugging. Check CloudWatch logs to see:
- What error is occurring in `handle_metadata`
- Why the route matching might be failing
- If dashboard data files are missing

## Verification

Test the API:
```bash
curl https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata
```

This should hit Lambda and return either:
- Success response (if Lambda works)
- 500 error (current - Lambda is failing)

---

**Date**: 2026-01-13
**Status**: ✅ API Gateway deployed and routing to Lambda
