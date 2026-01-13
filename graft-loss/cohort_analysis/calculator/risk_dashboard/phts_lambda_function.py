#!/usr/bin/env python3
"""
AWS Lambda function for PHTS Risk Calculator Dashboard API.

This function:
1. Loads trained survival models (CatBoost, XGBoost, XGBoost RF)
2. Accepts clinical feature inputs
3. Computes risk predictions
4. Returns risk scores with top causal factors from FFA analysis

Endpoints:
- GET /metadata - Returns available cohorts and causal factors
- POST /risk - Calculates risk score from clinical features
- POST /causal - Returns causal factor explanations

Environment Variables:
- PHTS_BUCKET: S3 bucket name (default: phts-calculator)
- MODEL_BASE_PATH: Path to models in container (default: /var/task/models)
- DASHBOARD_DATA_PATH: Path to dashboard data (default: /var/task/dashboard_data)
"""

import json
import os
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
import time

import boto3
from botocore.exceptions import ClientError

# Try to import model libraries
try:
    import numpy as np
    import pandas as pd
    from catboost import CatBoostRegressor
    import xgboost as xgb
    # Set XGBoost verbosity globally to avoid logging parameter conflicts
    # This must be done before any XGBoost operations
    import os
    os.environ['XGBOOST_VERBOSE'] = '0'  # Disable XGBoost logging
    # Try to set CatBoost verbosity globally (may not be supported in all versions)
    try:
        os.environ['CATBOOST_VERBOSE'] = '0'
    except:
        pass
    MODEL_LIBS_AVAILABLE = True
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    logger.info("Model libraries imported successfully")
except ImportError as e:
    MODEL_LIBS_AVAILABLE = False
    logger = logging.getLogger()
    logger.setLevel(logging.ERROR)
    logger.error(f"Warning: Model libraries not available: {e}. Model inference will fail.")

# Configuration
S3_BUCKET = os.environ.get("PHTS_BUCKET", "jerome-dixon.io")
S3_PREFIX = os.environ.get("S3_PREFIX", "uva/phts-risk-calculator")
# Lambda container paths (models are baked into container)
MODEL_BASE_PATH = os.environ.get("MODEL_BASE_PATH", "/var/task/models")
DASHBOARD_DATA_PATH = os.environ.get("DASHBOARD_DATA_PATH", "/var/task/dashboard_data")
RISK_DISTRIBUTION_PATH = os.environ.get("RISK_DISTRIBUTION_PATH", "/var/task/risk_distributions")
MODEL_CACHE_TTL = int(os.environ.get("MODEL_CACHE_TTL", "3600"))

# Available cohorts
# All three cohorts have trained models and dashboard data
AVAILABLE_COHORTS = ["CHD", "Combined", "Myocardio"]
COHORTS_WITH_DATA = ["CHD", "Combined", "Myocardio"]

# Risk score distributions for normalization (loaded on demand)
_risk_distributions: Dict[str, Dict[str, Any]] = {}  # All cohorts have trained models

# In-memory model cache
_model_cache: Dict[str, Dict[str, Any]] = {}
_cache_timestamps: Dict[str, float] = {}
_dashboard_data_cache: Dict[str, Dict[str, Any]] = {}

# Initialize S3 client (may fail if credentials not available, but that's OK for container)
try:
    s3_client = boto3.client("s3")
except Exception as e:
    s3_client = None
    if 'logger' in globals():
        logger.warning(f"Could not initialize S3 client: {e}")

# Set up logging (if not already set by model import)
if 'logger' not in globals():
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)


def _response(status_code: int, body: Dict[str, Any], headers: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    """Standard API Gateway proxy response."""
    default_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token",
        "Access-Control-Allow-Credentials": "false",
        "Access-Control-Max-Age": "3600",
    }
    if headers:
        default_headers.update(headers)
    
    return {
        "statusCode": status_code,
        "headers": default_headers,
        "body": json.dumps(body),
    }


def get_feature_metadata(cohort: str) -> Dict[str, str]:
    """
    Get feature type metadata (binary vs numeric) from model and training data.
    
    Returns:
        Dictionary mapping feature names to their types: 'binary' or 'numeric'
    """
    feature_metadata = {}
    
    try:
        # Try to load a sample of training data to determine feature types
        # Use the same data loading logic as compute_risk_distributions
        import sys
        from pathlib import Path
        
        # Add paths for imports
        project_root = Path(__file__).parent.parent.parent.parent
        sys.path.insert(0, str(project_root))
        sys.path.insert(0, str(Path(__file__).parent.parent))
        
        try:
            # Import data loading function
            import sys
            from pathlib import Path
            project_root = Path(__file__).parent.parent.parent.parent
            sys.path.insert(0, str(project_root))
            sys.path.insert(0, str(Path(__file__).parent.parent))
            
            from run_shap_ffa_workflow import prepare_calculator_features, load_calculator_data_for_shap
            import pandas as pd
            
            # Load a sample of data (use same function as SHAP workflow)
            df = load_calculator_data_for_shap(cohort)
            if df is not None and len(df) > 0:
                # Filter to cohort if needed
                if 'prim_dx' in df.columns:
                    if cohort == 'CHD':
                        df = df[df['prim_dx'].isin(['CHD', 'Congenital Heart Disease'])].copy()
                    elif cohort == 'Myocardio':
                        df = df[df['prim_dx'].isin(['Myocardio', 'Cardiomyopathy', 'Myocarditis'])].copy()
                    # Combined uses all data
                
                # Prepare features
                df_prepared = prepare_calculator_features(df.copy())
                
                # Load model to get feature names
                best_model_type = get_best_model(cohort)
                model = load_model(cohort, best_model_type)
                
                if model:
                    # Get feature names
                    if best_model_type == 'catboost' and hasattr(model, 'feature_names_'):
                        feature_names = model.feature_names_
                    elif best_model_type in ['xgboost', 'xgboost_rf']:
                        # Try to get from model
                        try:
                            feature_names = model.feature_names if hasattr(model, 'feature_names') else []
                        except:
                            feature_names = []
                    else:
                        feature_names = []
                    
                    # Determine type for each feature
                    for feature_name in feature_names:
                        if feature_name in df_prepared.columns:
                            col_data = df_prepared[feature_name].dropna()
                            
                            if len(col_data) > 0:
                                # Check if binary: only contains 0 and/or 1
                                unique_vals = set(col_data.unique())
                                if unique_vals.issubset({0, 1, 0.0, 1.0}):
                                    feature_metadata[feature_name] = 'binary'
                                else:
                                    feature_metadata[feature_name] = 'numeric'
                            else:
                                # Default to numeric if no data
                                feature_metadata[feature_name] = 'numeric'
                        else:
                            # Default to numeric if feature not in data
                            feature_metadata[feature_name] = 'numeric'
            
        except Exception as e:
            logger.warning(f"Could not determine feature metadata from data: {e}")
            # Return empty dict - will fall back to inference
    
    except Exception as e:
        logger.warning(f"Error getting feature metadata: {e}")
    
    return feature_metadata


def load_dashboard_data(cohort: str) -> Dict[str, Any]:
    """
    Load dashboard data (causal factors) for a cohort.
    
    Tries:
    1. Container filesystem (DASHBOARD_DATA_PATH)
    2. S3 bucket
    """
    if cohort in _dashboard_data_cache:
        return _dashboard_data_cache[cohort]
    
    # Try container filesystem first
    container_path = Path(DASHBOARD_DATA_PATH) / cohort / "dashboard_data.json"
    if container_path.exists():
        logger.info(f"Loading dashboard data from container: {container_path}")
        with open(container_path, 'r') as f:
            data = json.load(f)
        _dashboard_data_cache[cohort] = data
        return data
    
    # Try S3 (if client is available)
    if s3_client is not None:
        s3_key = f"{S3_PREFIX}/dashboard_data/{cohort}/dashboard_data.json"
        try:
            logger.info(f"Loading dashboard data from S3: s3://{S3_BUCKET}/{s3_key}")
            response = s3_client.get_object(Bucket=S3_BUCKET, Key=s3_key)
            data = json.loads(response['Body'].read().decode('utf-8'))
            _dashboard_data_cache[cohort] = data
            return data
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchKey':
                logger.warning(f"Dashboard data not found in S3: {s3_key}")
            else:
                logger.error(f"Error loading dashboard data from S3: {e}")
        except Exception as e:
            logger.error(f"Error accessing S3: {e}")
    
    # If we get here, dashboard data not found
    raise FileNotFoundError(f"Dashboard data not found for cohort: {cohort}")


def load_risk_distribution(cohort: str) -> Optional[Dict[str, Any]]:
    """
    Load risk score distribution for a cohort (for normalization).
    
    Tries:
    1. Container filesystem (RISK_DISTRIBUTION_PATH)
    2. S3 bucket
    
    Returns None if not found (will use raw scores).
    """
    if cohort in _risk_distributions:
        return _risk_distributions[cohort]
    
    # Try container filesystem first
    container_path = Path(RISK_DISTRIBUTION_PATH) / "risk_distributions.json"
    if container_path.exists():
        logger.info(f"Loading risk distribution from container: {container_path}")
        try:
            with open(container_path, 'r') as f:
                all_distributions = json.load(f)
                if cohort in all_distributions:
                    _risk_distributions[cohort] = all_distributions[cohort]
                    return all_distributions[cohort]
        except Exception as e:
            logger.warning(f"Error loading risk distribution from container: {e}")
    
    # Try S3 (if client is available)
    if s3_client is not None:
        s3_key = f"{S3_PREFIX}/risk_distributions/risk_distributions.json"
        try:
            logger.info(f"Loading risk distribution from S3: s3://{S3_BUCKET}/{s3_key}")
            response = s3_client.get_object(Bucket=S3_BUCKET, Key=s3_key)
            all_distributions = json.loads(response['Body'].read().decode('utf-8'))
            if cohort in all_distributions:
                _risk_distributions[cohort] = all_distributions[cohort]
                return all_distributions[cohort]
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchKey':
                logger.warning(f"Risk distribution not found in S3: {s3_key}")
            else:
                logger.error(f"Error loading risk distribution from S3: {e}")
        except Exception as e:
            logger.error(f"Error accessing S3: {e}")
    
    # Return None if not found (will use raw scores)
    logger.warning(f"Risk distribution not found for {cohort}, using raw scores")
    return None


def normalize_risk_score(raw_score: float, cohort: str, method: str = "percentile") -> Dict[str, Any]:
    """
    Normalize risk score for interpretability across cohorts.
    
    Args:
        raw_score: Raw prediction from model
        cohort: Cohort name
        method: Normalization method ("percentile" or "0-1")
    
    Returns:
        Dictionary with normalized scores and metadata
    """
    distribution = load_risk_distribution(cohort)
    
    if distribution is None:
        # No distribution available - return raw score with note
        return {
            'raw_score': raw_score,
            'normalized_score': raw_score,
            'percentile': None,
            'normalization_method': 'none',
            'note': 'Distribution not available, using raw score'
        }
    
    percentiles = distribution.get('percentiles', {})
    if not percentiles:
        return {
            'raw_score': raw_score,
            'normalized_score': raw_score,
            'percentile': None,
            'normalization_method': 'none',
            'note': 'Percentiles not available, using raw score'
        }
    
    # Calculate percentile rank
    percentile_score = _raw_to_percentile(raw_score, percentiles)
    
    if method == "percentile":
        return {
            'raw_score': raw_score,
            'normalized_score': percentile_score,  # 0-100 percentile
            'percentile': percentile_score,
            'normalization_method': 'percentile',
            'risk_band': _percentile_to_risk_band(percentile_score)
        }
    elif method == "0-1":
        # Min-max normalization to 0-1
        normalized = _normalize_0_1(raw_score, percentiles)
        return {
            'raw_score': raw_score,
            'normalized_score': normalized,  # 0-1 scale
            'percentile': percentile_score,
            'normalization_method': '0-1',
            'risk_band': _percentile_to_risk_band(percentile_score)
        }
    else:
        return {
            'raw_score': raw_score,
            'normalized_score': raw_score,
            'percentile': percentile_score,
            'normalization_method': 'none',
            'note': f'Unknown method: {method}'
        }


def _raw_to_percentile(raw_score: float, percentiles: Dict[str, float]) -> float:
    """
    Convert raw risk score to percentile (0-100) using linear interpolation.
    """
    p_min = percentiles.get('min', 0)
    p_max = percentiles.get('max', 100)
    
    if raw_score <= percentiles.get('p5', p_min):
        p5 = percentiles.get('p5', p_min)
        if p5 > p_min:
            return max(0.0, 5.0 * (raw_score - p_min) / (p5 - p_min))
        return 0.0
    elif raw_score <= percentiles.get('p25', percentiles.get('median', 0)):
        p5 = percentiles.get('p5', p_min)
        p25 = percentiles.get('p25', percentiles.get('median', 0))
        if p25 > p5:
            return 5.0 + 20.0 * (raw_score - p5) / (p25 - p5)
        return 5.0
    elif raw_score <= percentiles.get('p50', percentiles.get('median', 0)):
        p25 = percentiles.get('p25', percentiles.get('median', 0))
        p50 = percentiles.get('p50', percentiles.get('median', 0))
        if p50 > p25:
            return 25.0 + 25.0 * (raw_score - p25) / (p50 - p25)
        return 25.0
    elif raw_score <= percentiles.get('p75', p_max):
        p50 = percentiles.get('p50', percentiles.get('median', 0))
        p75 = percentiles.get('p75', p_max)
        if p75 > p50:
            return 50.0 + 25.0 * (raw_score - p50) / (p75 - p50)
        return 50.0
    elif raw_score <= percentiles.get('p90', p_max):
        p75 = percentiles.get('p75', p_max)
        p90 = percentiles.get('p90', p_max)
        if p90 > p75:
            return 75.0 + 15.0 * (raw_score - p75) / (p90 - p75)
        return 75.0
    elif raw_score <= percentiles.get('p95', p_max):
        p90 = percentiles.get('p90', p_max)
        p95 = percentiles.get('p95', p_max)
        if p95 > p90:
            return 90.0 + 5.0 * (raw_score - p90) / (p95 - p90)
        return 90.0
    else:
        p95 = percentiles.get('p95', p_max)
        if p_max > p95:
            return min(100.0, 95.0 + 5.0 * (raw_score - p95) / (p_max - p95))
        return 95.0


def _normalize_0_1(raw_score: float, percentiles: Dict[str, float]) -> float:
    """Min-max normalization to 0-1 scale."""
    p_min = percentiles.get('min', 0)
    p_max = percentiles.get('max', 1)
    if p_max == p_min:
        return 0.5
    normalized = (raw_score - p_min) / (p_max - p_min)
    return max(0.0, min(1.0, normalized))


def _percentile_to_risk_band(percentile: float) -> str:
    """Convert percentile to risk band."""
    if percentile < 25:
        return "low"
    elif percentile < 75:
        return "medium"
    elif percentile < 90:
        return "high"
    else:
        return "very_high"


def load_model(cohort: str, model_type: str) -> Any:
    """
    Load a trained model for a cohort.
    
    Args:
        cohort: Cohort name (CHD, Combined, Myocardio)
        model_type: Model type ('catboost', 'xgboost', 'xgboost_rf')
    
    Returns:
        Loaded model object
    """
    cache_key = f"{cohort}_{model_type}"
    
    # Check cache
    if cache_key in _model_cache:
        if time.time() - _cache_timestamps[cache_key] < MODEL_CACHE_TTL:
            logger.info(f"Using cached model: {cache_key}")
            return _model_cache[cache_key]['model']
    
    if not MODEL_LIBS_AVAILABLE:
        raise RuntimeError("Model libraries not available")
    
    # Try container filesystem first
    container_model_path = Path(MODEL_BASE_PATH) / cohort
    
    if model_type == 'catboost':
        model_path = container_model_path / "catboost_model.cbm"
        if model_path.exists():
            logger.info(f"Loading CatBoost model from container: {model_path}")
            # Model is now saved with only logging_level='Silent' (no conflicting verbose params)
            # Load with logging_level='Silent' to match training
            model = CatBoostRegressor(logging_level='Silent')
            model.load_model(str(model_path))
            _model_cache[cache_key] = {'model': model, 'type': 'catboost'}
            _cache_timestamps[cache_key] = time.time()
            return model
    
    elif model_type in ['xgboost', 'xgboost_rf']:
        model_filename = "xgboost_model.ubj" if model_type == 'xgboost' else "xgboost_rf_model.ubj"
        model_path = container_model_path / model_filename
        if model_path.exists():
            logger.info(f"Loading XGBoost model from container: {model_path}")
            # Create Booster without parameters - logging is controlled globally
            model = xgb.Booster()
            model.load_model(str(model_path))
            _model_cache[cache_key] = {'model': model, 'type': 'xgboost'}
            _cache_timestamps[cache_key] = time.time()
            return model
    
    # Try S3
    s3_key = f"{S3_PREFIX}/models/{cohort}/{model_filename if model_type != 'catboost' else 'catboost_model.cbm'}"
    try:
        logger.info(f"Loading model from S3: s3://{S3_BUCKET}/{s3_key}")
        with open(f"/tmp/{model_filename if model_type != 'catboost' else 'catboost_model.cbm'}", 'wb') as f:
            s3_client.download_fileobj(S3_BUCKET, s3_key, f)
        
        if model_type == 'catboost':
            # Model is now saved with only logging_level='Silent' (no conflicting verbose params)
            model = CatBoostRegressor(logging_level='Silent')
            model.load_model(f"/tmp/catboost_model.cbm")
        else:
            # Create Booster without parameters - logging is controlled globally
            model = xgb.Booster()
            model.load_model(f"/tmp/{model_filename}")
        
        _model_cache[cache_key] = {'model': model, 'type': model_type}
        _cache_timestamps[cache_key] = time.time()
        return model
    
    except ClientError as e:
        raise FileNotFoundError(f"Model not found for {cohort}/{model_type}: {e}")


def get_best_model(cohort: str) -> str:
    """Get the best model type for a cohort from best_model.txt."""
    # Try container filesystem
    best_model_path = Path(MODEL_BASE_PATH) / cohort / "best_model.txt"
    if best_model_path.exists():
        with open(best_model_path, 'r') as f:
            for line in f:
                if line.startswith("Best Model:"):
                    best_model = line.split("Best Model:")[1].strip()
                    # Normalize model name
                    if "XGBoost RF" in best_model:
                        return "xgboost_rf"
                    elif "XGBoost" in best_model:
                        return "xgboost"
                    elif "CatBoost" in best_model:
                        return "catboost"
    
    # Default to XGBoost if not found
    return "xgboost"


def prepare_feature_vector(features: Dict[str, Any], feature_names: List[str]) -> np.ndarray:
    """
    Prepare feature vector from user inputs.
    
    Args:
        features: Dictionary of feature values from user input
        feature_names: List of expected feature names (from model)
    
    Returns:
        Feature vector as numpy array
    """
    feature_vector = np.zeros(len(feature_names), dtype=np.float32)
    
    for i, feature_name in enumerate(feature_names):
        if feature_name in features:
            value = features[feature_name]
            # Handle different input types
            if isinstance(value, (int, float)):
                feature_vector[i] = float(value)
            elif isinstance(value, bool):
                feature_vector[i] = 1.0 if value else 0.0
            elif isinstance(value, str):
                # Try to convert string to float
                try:
                    feature_vector[i] = float(value)
                except ValueError:
                    # If conversion fails, treat as binary (present/absent)
                    feature_vector[i] = 1.0 if value.lower() in ['true', 'yes', '1', 'present'] else 0.0
    
    return feature_vector


def predict_risk_survival(
    cohort: str,
    features: Dict[str, Any],
    use_best_model_only: bool = True
) -> Dict[str, Any]:
    """
    Predict graft loss risk using survival models.
    
    Args:
        cohort: Cohort name
        features: Dictionary of clinical feature values
        use_best_model_only: If True, use only the best model; if False, use ensemble
    
    Returns:
        Dictionary with risk predictions and model info
    """
    if not MODEL_LIBS_AVAILABLE:
        raise RuntimeError("Model libraries not available")
    
    # Get best model
    best_model_type = get_best_model(cohort)
    
    if use_best_model_only:
        # Use only the best model
        model = load_model(cohort, best_model_type)
        
        # Get feature names from model
        if best_model_type == 'catboost':
            feature_names = model.feature_names_ if hasattr(model, 'feature_names_') else []
        else:  # XGBoost
            # XGBoost Booster stores feature names differently
            try:
                feature_names = model.feature_names if hasattr(model, 'feature_names') else []
            except:
                feature_names = []
            
            # If feature names not available, try to load from model JSON or use defaults
            if not feature_names:
                logger.warning("Feature names not available from model, using feature indices")
                # Try to infer from input features dict
                feature_names = sorted(features.keys())
        
        # Prepare feature vector
        feature_vector = prepare_feature_vector(features, feature_names)
        
        # Predict
        if best_model_type == 'catboost':
            # Model is now saved correctly with only logging_level='Silent'
            # Normal predict() should work without conflicts
            risk_score = model.predict(feature_vector.reshape(1, -1))[0]
        else:  # XGBoost
            # Create DMatrix without logging parameters - logging is controlled globally
            dmatrix = xgb.DMatrix(feature_vector.reshape(1, -1), feature_names=feature_names)
            risk_score = model.predict(dmatrix)[0]
        
        return {
            'risk_score': float(risk_score),
            'model_used': best_model_type,
            'models_used': [best_model_type],
            'ensemble': False
        }
    else:
        # Use ensemble of all available models
        predictions = {}
        models_used = []
        
        for model_type in ['catboost', 'xgboost', 'xgboost_rf']:
            try:
                model = load_model(cohort, model_type)
                
                if model_type == 'catboost':
                    feature_names = model.feature_names_ if hasattr(model, 'feature_names_') else []
                else:
                    try:
                        feature_names = model.feature_names if hasattr(model, 'feature_names') else []
                    except:
                        feature_names = []
                
                if not feature_names:
                    # Infer from input features
                    feature_names = sorted(features.keys())
                
                feature_vector = prepare_feature_vector(features, feature_names)
                
                if model_type == 'catboost':
                    # Model is now saved correctly with only logging_level='Silent'
                    # Normal predict() should work without conflicts
                    pred = model.predict(feature_vector.reshape(1, -1))[0]
                else:
                    # Create DMatrix without logging parameters - logging is controlled globally
                    dmatrix = xgb.DMatrix(feature_vector.reshape(1, -1), feature_names=feature_names)
                    pred = model.predict(dmatrix)[0]
                
                predictions[model_type] = float(pred)
                models_used.append(model_type)
            except Exception as e:
                logger.warning(f"Failed to load/predict with {model_type}: {e}")
                continue
        
        if not predictions:
            raise RuntimeError("No models available for prediction")
        
        # Average predictions
        ensemble_score = np.mean(list(predictions.values()))
        
        return {
            'risk_score': float(ensemble_score),
            'model_predictions': predictions,
            'models_used': models_used,
            'ensemble': True
        }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for API Gateway proxy integration.
    """
    # Ensure logger is available and log that handler was called
    try:
        logger.info("Lambda handler invoked")
        logger.info(f"Event: {json.dumps(event)}")
    except Exception as e:
        # If logging fails, at least try to print
        print(f"Lambda handler invoked, but logging failed: {e}")
    
    try:
        method = event.get("httpMethod", "GET")
        
        # API Gateway proxy integration can provide path in multiple places
        # Try to get path from various locations
        path = event.get("path", "")
        resource = event.get("resource", "")
        request_context = event.get("requestContext", {})
        path_from_context = request_context.get("path", "")
        resource_path = request_context.get("resourcePath", "")
        
        # Also check pathParameters which might have the route
        path_params = event.get("pathParameters", {}) or {}
        
        # Try to determine the actual route
        # For API Gateway proxy, the route might be in resource or we need to infer from the request
        actual_path = path or path_from_context or resource or resource_path
        
        # If still empty, try to get from the raw request path in requestContext
        if not actual_path and request_context:
            # Check for stage and path combination
            stage = request_context.get("stage", "")
            if stage:
                # The path might be constructed from stage + resource
                actual_path = f"/{stage}{resource}" if resource else f"/{stage}"
        
        # Normalize path - remove leading/trailing slashes
        path_clean = actual_path.strip("/") if actual_path else ""
        
        logger.info(f"Processing request: method={method}, path='{path}', resource='{resource}', actual_path='{actual_path}', path_clean='{path_clean}'")
        logger.info(f"Full event keys: {list(event.keys())}")
        logger.info(f"RequestContext keys: {list(request_context.keys()) if request_context else 'None'}")
        
        if method == "OPTIONS":
            return _response(200, {"message": "OK"})
        
        # Match routes - check if path contains metadata, risk, or causal
        # Handle various formats: "/metadata", "/prod/metadata", "metadata", etc.
        is_metadata = ("metadata" in path_clean.lower() if path_clean else False)
        is_risk = ("risk" in path_clean.lower() if path_clean else False)
        is_causal = ("causal" in path_clean.lower() if path_clean else False)
        
        # Also check if the resource directly matches
        resource_clean = resource.strip("/") if resource else ""
        if not is_metadata and not is_risk and not is_causal:
            is_metadata = ("metadata" in resource_clean.lower() if resource_clean else False)
            is_risk = ("risk" in resource_clean.lower() if resource_clean else False)
            is_causal = ("causal" in resource_clean.lower() if resource_clean else False)
        
        # If path is empty but we have a GET request, assume it's /metadata
        # This handles cases where API Gateway doesn't populate path/resource correctly
        if not is_metadata and not is_risk and not is_causal:
            if not path_clean and not resource_clean and method == "GET":
                logger.info("Path is empty for GET request, assuming /metadata route")
                is_metadata = True
        
        if method == "GET" and is_metadata:
            logger.info("Matched GET /metadata route")
            try:
                return handle_metadata(event)
            except Exception as e:
                logger.error(f"Error in handle_metadata: {e}", exc_info=True)
                raise
        elif method == "POST" and is_risk:
            logger.info("Matched POST /risk route")
            return handle_risk(event)
        elif method == "POST" and is_causal:
            logger.info("Matched POST /causal route")
            return handle_causal(event)
        
        # If no match, return 404 with comprehensive debug info
        logger.warning(f"No route matched: method={method}, path='{path}', resource='{resource}', actual_path='{actual_path}'")
        return _response(404, {
            "error": f"Unsupported route: {method} {actual_path or '(empty)'}",
            "debug": {
                "path": path,
                "resource": resource,
                "path_from_context": path_from_context,
                "resource_path": resource_path,
                "actual_path": actual_path,
                "path_clean": path_clean,
                "httpMethod": method,
                "event_keys": list(event.keys()),
                "requestContext_keys": list(request_context.keys()) if request_context else None,
                "available_routes": ["GET /metadata", "POST /risk", "POST /causal"]
            }
        })
    
    except Exception as exc:
        import traceback
        error_details = traceback.format_exc()
        try:
            logger.error(f"Error in lambda_handler: {error_details}")
        except:
            print(f"Error in lambda_handler (logging failed): {error_details}")
        
        # Return error with full details for debugging
        error_response = {
            "error": "Internal server error",
            "message": str(exc),
            "type": type(exc).__name__,
            "traceback": error_details
        }
        
        try:
            return _response(500, error_response)
        except Exception as e:
            # If _response fails, return minimal response
            return {
                "statusCode": 500,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Internal server error", "details": str(exc)})
            }


def handle_metadata(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    GET /metadata - Returns available cohorts, causal factors, and API configuration.
    
    Also returns the API Gateway URL so the frontend can use it dynamically.
    """
    try:
        logger.info("handle_metadata called")
        
        # Safely get query parameters
        query_params = event.get("queryStringParameters") or {}
        cohort = query_params.get("cohort") if isinstance(query_params, dict) else None
        logger.info(f"Requested cohort: {cohort}")
        
        # Get API Gateway URL from environment variable or construct from request
        api_url = os.environ.get("API_GATEWAY_URL")
        if not api_url:
            # Try to construct from request context
            request_context = event.get("requestContext", {})
            if request_context:
                domain = request_context.get("domainName")
                stage = request_context.get("stage")
                if domain and stage:
                    api_url = f"https://{domain}/{stage}"
        
        if cohort and cohort in AVAILABLE_COHORTS:
            # Load dashboard data for specific cohort
            try:
                dashboard_data = load_dashboard_data(cohort)
                # Get feature metadata (binary vs numeric)
                feature_metadata = get_feature_metadata(cohort)
                return _response(200, {
                    "cohort": cohort,
                    "available_cohorts": AVAILABLE_COHORTS,
                    "causal_factors": dashboard_data.get("top_causal_factors", []),
                    "summary": dashboard_data.get("summary", {}),
                    "feature_metadata": feature_metadata,  # Map of feature_name -> 'binary' or 'numeric'
                    "api_url": api_url
                })
            except Exception as e:
                logger.warning(f"Could not load dashboard data for {cohort}: {e}")
                # Return response even if dashboard data is missing
                return _response(200, {
                    "cohort": cohort,
                    "available_cohorts": AVAILABLE_COHORTS,
                    "causal_factors": [],
                    "summary": {},
                    "warning": f"Dashboard data not available: {str(e)}",
                    "api_url": api_url
                })
        else:
            # Return all cohorts (gracefully handle missing data)
            all_causal_factors = {}
            available_cohorts_with_data = []
            
            for c in AVAILABLE_COHORTS:
                try:
                    logger.info(f"Loading dashboard data for cohort: {c}")
                    dashboard_data = load_dashboard_data(c)
                    # Get feature metadata for this cohort
                    feature_metadata = get_feature_metadata(c)
                    all_causal_factors[c] = {
                        "top_causal_factors": dashboard_data.get("top_causal_factors", []),
                        "summary": dashboard_data.get("summary", {}),
                        "feature_metadata": feature_metadata
                    }
                    available_cohorts_with_data.append(c)
                    logger.info(f"Successfully loaded dashboard data for {c}")
                except FileNotFoundError as e:
                    logger.warning(f"Dashboard data file not found for {c}: {e}")
                    # Still include the cohort but with empty data
                    all_causal_factors[c] = {
                        "top_causal_factors": [],
                        "summary": {},
                        "error": f"Data file not found: {str(e)}"
                    }
                except Exception as e:
                    logger.error(f"Error loading dashboard data for {c}: {e}", exc_info=True)
                    # Still include the cohort but with empty data
                    all_causal_factors[c] = {
                        "top_causal_factors": [],
                        "summary": {},
                        "error": f"Error loading data: {str(e)}"
                    }
            
            return _response(200, {
                "available_cohorts": AVAILABLE_COHORTS,
                "cohorts_with_data": available_cohorts_with_data,
                "causal_factors_by_cohort": all_causal_factors,
                "api_url": api_url
            })
    
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        logger.error(f"Error in handle_metadata: {e}")
        logger.error(f"Traceback: {error_details}")
        # Return a response even on error, so we can see what went wrong
        return _response(500, {
            "error": "Internal server error",
            "message": str(e),
            "traceback": error_details
        })


def handle_risk(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    POST /risk - Calculate risk score from clinical features.
    
    Request body:
    {
        "cohort": "Combined",
        "features": {
            "egfr_tx": 60.0,
            "txbun_r": 20.0,
            "ltxtrach": 1,
            ...
        },
        "use_ensemble": false  // optional, default: false (use best model only)
    }
    """
    try:
        body = json.loads(event.get("body") or "{}")
        cohort = body.get("cohort", "Combined")
        
        if cohort not in AVAILABLE_COHORTS:
            return _response(400, {"error": f"Invalid cohort. Must be one of: {AVAILABLE_COHORTS}"})
        
        features = body.get("features", {})
        if not features:
            return _response(400, {"error": "No features provided"})
        
        use_ensemble = body.get("use_ensemble", False)
        
        # Predict risk
        result = predict_risk_survival(cohort, features, use_best_model_only=not use_ensemble)
        
        # Load causal factors
        try:
            dashboard_data = load_dashboard_data(cohort)
            top_causal = dashboard_data.get("top_causal_factors", [])
        except Exception as e:
            logger.warning(f"Could not load causal factors: {e}")
            top_causal = []
        
        # Normalize risk score for interpretability
        raw_score = result['risk_score']
        normalization = normalize_risk_score(raw_score, cohort, method="percentile")
        
        # Use normalized score and percentile for display
        normalized_score = normalization.get('normalized_score', raw_score)
        percentile = normalization.get('percentile')
        risk_band = normalization.get('risk_band', 'medium')
        
        return _response(200, {
            "cohort": cohort,
            "risk_score": normalized_score,  # Normalized score (percentile 0-100)
            "raw_score": raw_score,  # Original raw prediction
            "percentile": percentile,  # Percentile rank (0-100)
            "risk_band": risk_band,
            "model_info": {
                "model_used": result.get("model_used"),
                "models_used": result.get("models_used", []),
                "ensemble": result.get("ensemble", False)
            },
            "top_causal_factors": top_causal[:10],  # Top 10 causal factors
            "timestamp": time.time()
        })
    
    except Exception as e:
        import traceback
        logger.error(f"Error in handle_risk: {e}\n{traceback.format_exc()}")
        return _response(500, {"error": str(e)})


def handle_causal(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    POST /causal - Returns causal factor explanations.
    
    Request body:
    {
        "cohort": "Combined",
        "top_k": 10  // optional, default: 10
    }
    """
    try:
        body = json.loads(event.get("body") or "{}")
        cohort = body.get("cohort", "Combined")
        top_k = body.get("top_k", 10)
        
        if cohort not in AVAILABLE_COHORTS:
            return _response(400, {"error": f"Invalid cohort. Must be one of: {AVAILABLE_COHORTS}"})
        
        dashboard_data = load_dashboard_data(cohort)
        top_causal = dashboard_data.get("top_causal_factors", [])[:top_k]
        
        return _response(200, {
            "cohort": cohort,
            "top_causal_factors": top_causal,
            "summary": dashboard_data.get("summary", {})
        })
    
    except Exception as e:
        logger.error(f"Error in handle_causal: {e}")
        return _response(500, {"error": str(e)})
