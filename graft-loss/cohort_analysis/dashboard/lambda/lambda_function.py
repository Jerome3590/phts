"""
AWS Lambda function for Cohort Risk Dashboard API.

Handles:
- GET /metadata - Get feature metadata and model information
- POST /risk - Calculate graft loss risk
- POST /risk/comparison - Compare risk scenarios
"""

import json
import os
import boto3
from typing import Dict, Any, Optional
from utils.model_loader import ModelLoader
from utils.predictor import RiskPredictor

# Initialize S3 client
s3_client = boto3.client('s3')
MODELS_BUCKET = os.environ.get('MODELS_BUCKET', 'uva-graft-loss-cohort-models')
MODELS_PREFIX = os.environ.get('MODELS_PREFIX', 'models/')

# Initialize model loader (cached across invocations)
model_loader = ModelLoader(s3_client, MODELS_BUCKET, MODELS_PREFIX)
predictor = RiskPredictor(model_loader)


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler function.
    
    Args:
        event: API Gateway event
        context: Lambda context
        
    Returns:
        API Gateway response
    """
    try:
        # Parse request
        path = event.get('path', '')
        http_method = event.get('httpMethod', '')
        body = event.get('body', '{}')
        
        # Parse body if present
        if body:
            try:
                body = json.loads(body) if isinstance(body, str) else body
            except json.JSONDecodeError:
                return create_response(400, {'error': 'Invalid JSON in request body'})
        
        # Route requests
        if path == '/metadata' and http_method == 'GET':
            return handle_metadata()
        elif path == '/risk' and http_method == 'POST':
            return handle_risk(body)
        elif path == '/risk/comparison' and http_method == 'POST':
            return handle_comparison(body)
        else:
            return create_response(404, {'error': 'Not found'})
            
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()
        return create_response(500, {'error': 'Internal server error', 'message': str(e)})


def handle_metadata() -> Dict[str, Any]:
    """Handle GET /metadata request."""
    try:
        # Load metadata from S3
        metadata = model_loader.load_metadata()
        
        return create_response(200, metadata)
    except Exception as e:
        return create_response(500, {'error': 'Failed to load metadata', 'message': str(e)})


def handle_risk(body: Dict[str, Any]) -> Dict[str, Any]:
    """Handle POST /risk request."""
    try:
        # Validate request
        cohort = body.get('cohort')
        features = body.get('features', {})
        
        if not cohort or cohort not in ['CHD', 'MyoCardio']:
            return create_response(400, {'error': 'Invalid cohort. Must be CHD or MyoCardio'})
        
        if not features:
            return create_response(400, {'error': 'Features required'})
        
        # Get prediction
        result = predictor.predict_risk(cohort, features)
        
        return create_response(200, result)
    except ValueError as e:
        return create_response(400, {'error': str(e)})
    except Exception as e:
        return create_response(500, {'error': 'Prediction failed', 'message': str(e)})


def handle_comparison(body: Dict[str, Any]) -> Dict[str, Any]:
    """Handle POST /risk/comparison request."""
    try:
        # Validate request
        cohort = body.get('cohort')
        baseline_features = body.get('baseline_features', {})
        intervention_features = body.get('intervention_features', {})
        
        if not cohort or cohort not in ['CHD', 'MyoCardio']:
            return create_response(400, {'error': 'Invalid cohort'})
        
        if not baseline_features or not intervention_features:
            return create_response(400, {'error': 'Both baseline and intervention features required'})
        
        # Get predictions
        baseline_result = predictor.predict_risk(cohort, baseline_features)
        intervention_result = predictor.predict_risk(cohort, intervention_features)
        
        # Calculate comparison
        comparison = {
            'baseline_risk': baseline_result['risk_score'],
            'intervention_risk': intervention_result['risk_score'],
            'risk_reduction': baseline_result['risk_score'] - intervention_result['risk_score'],
            'relative_risk_reduction': (
                (baseline_result['risk_score'] - intervention_result['risk_score']) /
                baseline_result['risk_score'] * 100
                if baseline_result['risk_score'] > 0 else 0
            ),
            'feature_changes': calculate_feature_changes(
                baseline_features,
                intervention_features,
                baseline_result.get('feature_contributions', {}),
                intervention_result.get('feature_contributions', {})
            )
        }
        
        return create_response(200, comparison)
    except ValueError as e:
        return create_response(400, {'error': str(e)})
    except Exception as e:
        return create_response(500, {'error': 'Comparison failed', 'message': str(e)})


def calculate_feature_changes(
    baseline_features: Dict[str, float],
    intervention_features: Dict[str, float],
    baseline_contributions: Dict[str, float],
    intervention_contributions: Dict[str, float]
) -> Dict[str, Dict[str, float]]:
    """Calculate feature changes and their impact."""
    changes = {}
    
    all_features = set(baseline_features.keys()) | set(intervention_features.keys())
    
    for feature in all_features:
        baseline_val = baseline_features.get(feature)
        intervention_val = intervention_features.get(feature)
        
        if baseline_val != intervention_val:
            baseline_contrib = baseline_contributions.get(feature, 0)
            intervention_contrib = intervention_contributions.get(feature, 0)
            impact = intervention_contrib - baseline_contrib
            
            changes[feature] = {
                'baseline': baseline_val,
                'intervention': intervention_val,
                'impact': impact
            }
    
    return changes


def create_response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    """Create API Gateway response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
        },
        'body': json.dumps(body)
    }

