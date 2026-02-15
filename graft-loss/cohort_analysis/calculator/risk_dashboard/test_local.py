#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Local testing script for PHTS Lambda function and API Gateway endpoints.

This script allows you to test the Lambda function locally without deploying to AWS.
It simulates API Gateway events and runs the Lambda handler directly.
"""

import json
import os
import sys
from pathlib import Path

# Fix Unicode encoding for Windows
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

# Add the current directory to path so we can import the Lambda function
sys.path.insert(0, str(Path(__file__).parent))

# Set up environment variables for local testing
os.environ.setdefault('MODEL_BASE_PATH', str(Path(__file__).parent / 'lambda_dir_phts' / 'models'))
os.environ.setdefault('MODEL_FEATURES_PATH', str(Path(__file__).parent / 'lambda_dir_phts' / 'model_features'))
os.environ.setdefault('DASHBOARD_DATA_PATH', str(Path(__file__).parent / 'lambda_dir_phts' / 'dashboard_data'))
os.environ.setdefault('RISK_DISTRIBUTION_PATH', str(Path(__file__).parent / 'lambda_dir_phts' / 'risk_distributions'))
os.environ.setdefault('PHTS_BUCKET', 'jerome-dixon.io')
os.environ.setdefault('S3_PREFIX', 'uva/phts-risk-calculator')
os.environ.setdefault('API_GATEWAY_URL', 'https://359vxflbzj.execute-api.us-east-1.amazonaws.com/prod')

# Import Lambda function
try:
    from phts_lambda_function import lambda_handler
except ImportError as e:
    print(f"Error importing Lambda function: {e}")
    print("Make sure you're in the risk_dashboard directory and dependencies are installed.")
    sys.exit(1)


def create_api_gateway_event(http_method, path, query_params=None, body=None, model_variant='top'):
    """Create a mock API Gateway event."""
    event = {
        "httpMethod": http_method,
        "path": path,
        "pathParameters": None,
        "queryStringParameters": query_params or {},
        "headers": {
            "Content-Type": "application/json",
            "Origin": "http://localhost:8000"
        },
        "body": json.dumps(body) if body else None,
        "isBase64Encoded": False,
        "requestContext": {
            "accountId": "123456789012",
            "apiId": "359vxflbzj",
            "domainName": "359vxflbzj.execute-api.us-east-1.amazonaws.com",
            "domainPrefix": "359vxflbzj",
            "httpMethod": http_method,
            "path": path,
            "protocol": "HTTP/1.1",
            "requestId": "test-request-id",
            "requestTime": "09/Apr/2015:12:34:56 +0000",
            "requestTimeEpoch": 1428582896000,
            "resourceId": "test-resource-id",
            "resourcePath": path,
            "stage": "prod"
        }
    }
    return event


def test_metadata_endpoint():
    """Test GET /metadata endpoint."""
    print("\n" + "="*80)
    print("Testing GET /metadata endpoint")
    print("="*80)
    
    event = create_api_gateway_event(
        http_method="GET",
        path="/metadata",
        query_params={"cohort": "Combined"}
    )
    
    try:
        response = lambda_handler(event, None)
        print(f"\nStatus Code: {response['statusCode']}")
        print(f"Headers: {json.dumps(response.get('headers', {}), indent=2)}")
        
        if response.get('body'):
            body = json.loads(response['body'])
            print(f"\nResponse Body:")
            print(json.dumps(body, indent=2))
        
        return response['statusCode'] == 200
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_risk_endpoint():
    """Test POST /risk endpoint (top-features model)."""
    print("\n" + "="*80)
    print("Testing POST /risk endpoint (Top Model - Combined_top)")
    print("="*80)
    
    body = {
        "cohort": "Combined",
        "model_variant": "top",
        "features": {
            "egfr_tx": 60.0,
            "txbun_r": 20.0,
            "txcreat_r": 1.0,
            "ltxtrach": 0,
            "txecmo": 0,
            "txnomcsd": 0,
            "chd_sv": 0,
            "donisch": 4.0,
            "txsa_r": 3.5,
            "txast": 30.0
        }
    }
    
    event = create_api_gateway_event(
        http_method="POST",
        path="/risk",
        body=body
    )
    
    try:
        response = lambda_handler(event, None)
        print(f"\nStatus Code: {response['statusCode']}")
        
        if response.get('body'):
            body = json.loads(response['body'])
            print(f"\nResponse Body:")
            print(json.dumps(body, indent=2))
            
            if 'risk_score' in body:
                print(f"\n✓ Risk Score: {body['risk_score']:.2f}%")
                print(f"✓ Risk Band: {body.get('risk_band', 'N/A')}")
                print(f"✓ Percentile: {body.get('percentile', 'N/A')}")
        
        return response['statusCode'] == 200
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_causal_endpoint():
    """Test POST /causal endpoint (top model)."""
    print("\n" + "="*80)
    print("Testing POST /causal endpoint (Top Model)")
    print("="*80)
    
    body = {
        "cohort": "Combined",
        "model_variant": "top",
        "top_k": 10
    }
    
    event = create_api_gateway_event(
        http_method="POST",
        path="/causal",
        body=body
    )
    
    try:
        response = lambda_handler(event, None)
        print(f"\nStatus Code: {response['statusCode']}")
        
        if response.get('body'):
            body = json.loads(response['body'])
            print(f"\nResponse Body:")
            print(json.dumps(body, indent=2))
            
            if 'top_causal_factors' in body:
                factors = body['top_causal_factors']
                print(f"\n[OK] Found {len(factors)} causal factors")
                if factors:
                    print("\nTop 5 factors:")
                    for i, factor in enumerate(factors[:5], 1):
                        importance = factor.get('importance', factor.get('combined_importance', 0))
                        print(f"  {i}. {factor['feature']}: {importance:.4f}")
        
        return response['statusCode'] == 200
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def check_prerequisites():
    """Check if required directories and files exist."""
    lambda_dir = Path(__file__).parent / 'lambda_dir_phts'
    issues = []
    
    if not lambda_dir.exists():
        issues.append("lambda_dir_phts/ directory not found")
        return issues
    
    # Check for model directories (model per cohort: at least one of CHD_top, Myocardio_top, Combined_top)
    model_dir = lambda_dir / 'models'
    if not model_dir.exists():
        issues.append("lambda_dir_phts/models/ not found")
    else:
        expected = ['CHD_top', 'Myocardio_top', 'Combined_top']
        found = [c for c in expected if (model_dir / c).exists()]
        if not found:
            issues.append("No cohort model dir found (expected one or more of CHD_top, Myocardio_top, Combined_top; run train_python_models.py --cohort <C> --top_features_only, then prepare_lambda_dir_phts.py)")
    
    dashboard_dir = lambda_dir / 'dashboard_data'
    if not dashboard_dir.exists():
        issues.append("lambda_dir_phts/dashboard_data/ not found")
    else:
        expected = ['CHD_top', 'Myocardio_top', 'Combined_top']
        found = [c for c in expected if (dashboard_dir / c).exists()]
        if not found:
            issues.append("No cohort dashboard data found (expected one or more of CHD_top, Myocardio_top, Combined_top; run run_shap_ffa_workflow.py --cohort <C> --model-variant top, then prepare_lambda_dir_phts.py)")
    
    return issues


def main():
    """Run all tests."""
    print("="*80)
    print("PHTS Lambda Function - Local Testing")
    print("="*80)
    print("\nTesting Lambda function locally (simulating API Gateway events)")
    print("Make sure lambda_dir_phts/ is prepared with models and data.")
    print()
    
    # Check prerequisites
    issues = check_prerequisites()
    if issues:
        print("[WARNING] Prerequisites check failed:")
        for issue in issues:
            print(f"  - {issue}")
        print("\nTo fix, run:")
        print("  python prepare_lambda_dir_phts.py")
        print("\nNote: The script will continue but tests may fail if models/data are missing.")
        print()
    
    results = []
    results.append(("Metadata (GET)", test_metadata_endpoint()))
    results.append(("Risk (POST)", test_risk_endpoint()))
    results.append(("Causal (POST)", test_causal_endpoint()))
    
    # Summary
    print("\n" + "="*80)
    print("Test Summary")
    print("="*80)
    for test_name, passed in results:
        status = "[PASS]" if passed else "[FAIL]"
        print(f"{status}: {test_name}")
    
    passed_count = sum(1 for _, passed in results if passed)
    total_count = len(results)
    print(f"\nTotal: {passed_count}/{total_count} tests passed")
    
    if passed_count == total_count:
        print("\n[SUCCESS] All tests passed!")
        return 0
    else:
        print("\n[WARNING] Some tests failed. Check output above for details.")
        print("\nNote: If models are not found, make sure lambda_dir_phts/ is prepared:")
        print("  python prepare_lambda_dir_phts.py")
        return 1


if __name__ == "__main__":
    sys.exit(main())
