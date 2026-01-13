# Website API URL Fix

## Problem

The website wasn't hitting the Lambda because the HTML file had a placeholder API URL (`https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod`) instead of the actual API Gateway URL.

## Solution

1. **Injected correct API Gateway URL** into `phts_dashboard.html`:
   - Replaced placeholder with: `https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod`
   - Set `window.LAMBDA_API_URL` variable for easy access

2. **Uploaded updated HTML to S3**:
   - File: `s3://jerome-dixon.io/uva/phts-risk-calculator/index.html`
   - Content-Type: `text/html`

## API Gateway URL

- **API ID**: `359vxflbzj`
- **Region**: `us-east-1`
- **Stage**: `prod`
- **Full URL**: `https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod`

## How It Works

The HTML file now:
1. Sets `window.LAMBDA_API_URL` on page load
2. Uses this URL for all API calls (`/metadata`, `/risk`, `/causal`)
3. Falls back to trying to fetch from metadata endpoint if needed

## Next Steps

1. **Test the website**: Open `https://jerome-dixon.io/uva/phts-risk-calculator/` in a browser
2. **Check browser console**: Look for API calls and any CORS errors
3. **Verify Lambda is being called**: Check CloudWatch logs for invocations from the website

## Files Updated

- `phts_dashboard.html` - API URL injected
- Deployed to: `s3://jerome-dixon.io/uva/phts-risk-calculator/index.html`

---

**Date**: 2026-01-13
**Status**: ✅ Fixed - Website should now call Lambda API
