# NetworkError Debugging Guide

## Issue

NetworkError when attempting to fetch resource from the website.

## What We've Fixed

1. ✅ **Lambda CORS Headers**: Updated to include all necessary CORS headers
2. ✅ **API Gateway OPTIONS**: Configured for all endpoints
3. ✅ **Enhanced Logging**: Added console logging to diagnose issues
4. ✅ **Error Handling**: Better error messages for network errors
5. ✅ **API Connection Testing**: Tests connection on page load

## Debugging Steps

### 1. Check Browser Console (F12)

Open the browser console and look for:
- API URL being used
- CORS error messages
- Network error details
- Console logs from our code

### 2. Check Network Tab

In browser DevTools > Network tab:
- Look for the failed request
- Check request URL
- Check response headers
- Look for CORS-related errors

### 3. Test API Directly

In browser console, run:
```javascript
fetch('https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod/metadata', {
  mode: 'cors'
})
.then(r => {
  console.log('Status:', r.status);
  console.log('Headers:', [...r.headers.entries()]);
  return r.json();
})
.then(d => console.log('Data:', d))
.catch(e => console.error('Error:', e));
```

### 4. Common Issues

#### Issue: API URL Not Set
**Symptom**: `LAMBDA_API_URL` is null or undefined
**Solution**: Check if `window.LAMBDA_API_URL` is set in HTML

#### Issue: CORS Preflight Failing
**Symptom**: OPTIONS request fails
**Solution**: Verify API Gateway OPTIONS method is configured

#### Issue: Missing CORS Headers
**Symptom**: Request succeeds but browser blocks
**Solution**: Verify Lambda returns CORS headers (✅ Done)

#### Issue: Mixed Content
**Symptom**: HTTPS page trying to call HTTP API
**Solution**: Ensure API URL uses HTTPS (✅ Done)

## Current Configuration

- **API URL**: `https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod`
- **CORS Headers**: `Access-Control-Allow-Origin: *`
- **Methods**: GET, POST, OPTIONS
- **Headers**: Content-Type, Authorization, etc.

## Next Steps

1. **Open browser console** and check for specific error
2. **Check Network tab** to see the actual request
3. **Test API directly** from console
4. **Share the specific error message** from browser console

The enhanced logging should help identify the exact issue.

---

**Status**: CORS configured, enhanced logging added, need browser console output to diagnose
