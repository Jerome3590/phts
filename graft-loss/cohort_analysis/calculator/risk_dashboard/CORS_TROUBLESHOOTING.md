# CORS Troubleshooting

## Issue

NetworkError when attempting to fetch resource from the website.

## Possible Causes

1. **CORS not configured correctly** - API Gateway or Lambda not returning proper CORS headers
2. **S3 bucket CORS** - S3 bucket might need CORS configuration
3. **API Gateway CORS** - OPTIONS method might not be working correctly
4. **Browser blocking** - Browser might be blocking the request

## What We've Done

### 1. Lambda Function CORS Headers ✅
Updated `_response()` function to include:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET,POST,OPTIONS`
- `Access-Control-Allow-Headers: Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token`
- `Access-Control-Max-Age: 3600`

### 2. API Gateway OPTIONS Methods ✅
- OPTIONS methods configured for all resources
- CORS headers set in integration responses

### 3. Enhanced Error Handling ✅
- Added console logging to diagnose issues
- Added explicit `mode: 'cors'` to fetch requests
- Better error messages for network errors

## Testing

### Test CORS from Browser Console

Open browser console on the website and run:
```javascript
fetch('https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata', {
  mode: 'cors'
})
.then(r => r.json())
.then(d => console.log('Success:', d))
.catch(e => console.error('Error:', e));
```

### Check Browser Console

Look for:
- CORS errors
- Network errors
- API URL being used
- Response headers

## Common Issues

### Issue 1: Preflight (OPTIONS) Request Failing
**Symptom**: NetworkError on OPTIONS request
**Solution**: Ensure API Gateway OPTIONS method is configured correctly

### Issue 2: Missing CORS Headers in Response
**Symptom**: Request succeeds but browser blocks due to missing headers
**Solution**: Ensure Lambda returns CORS headers (✅ Done)

### Issue 3: S3 Bucket CORS
**Symptom**: Website can't make requests
**Solution**: S3 bucket might need CORS configuration (usually not needed for static HTML)

## Next Steps

1. **Check browser console** for specific error message
2. **Test API directly** from browser console
3. **Verify API Gateway deployment** is up to date
4. **Check if S3 bucket needs CORS** (usually not needed)

## Verification Commands

```bash
# Test OPTIONS request
curl -X OPTIONS "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata" \
  -H "Origin: https://jerome-dixon.io" \
  -H "Access-Control-Request-Method: GET" \
  -v

# Test GET request
curl "https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata" \
  -H "Origin: https://jerome-dixon.io" \
  -v
```

Both should return `Access-Control-Allow-Origin: *` in headers.

---

**Status**: CORS headers configured, need to check browser console for specific error
