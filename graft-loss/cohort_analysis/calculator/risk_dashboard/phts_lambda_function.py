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
- GET /model-metrics - Returns deployed model metrics (C-index, AUC, AU-PRC, Recall) and optional S3 link
- POST /risk - Calculates risk score from clinical features
- POST /causal - Returns causal factor explanations

Environment Variables:
- PHTS_BUCKET: S3 bucket name (default: phts-calculator)
- METRICS_S3_URL: Optional URL to metrics file in S3 (e.g. https://bucket.s3.region.amazonaws.com/prefix/model_metrics.json)
- MODEL_BASE_PATH: Path to models in container (default: /var/task/models)
- MODEL_FEATURES_PATH: Path to model features (default: /var/task/model_features)
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
MODEL_FEATURES_PATH = os.environ.get("MODEL_FEATURES_PATH", "/var/task/model_features")
DASHBOARD_DATA_PATH = os.environ.get("DASHBOARD_DATA_PATH", "/var/task/dashboard_data")
RISK_DISTRIBUTION_PATH = os.environ.get("RISK_DISTRIBUTION_PATH", "/var/task/risk_distributions")
MODEL_CACHE_TTL = int(os.environ.get("MODEL_CACHE_TTL", "3600"))

# Model per cohort × variant: CHD_top, Myocardio_base, Combined_FULL, etc. (all cohorts: CHD, Myocardio, Combined; all variants: base, enhanced, top, wisotzkey, FULL)
AVAILABLE_COHORTS = ["CHD", "Myocardio", "Combined"]
COHORTS_WITH_DATA = ["CHD", "Myocardio", "Combined"]
MODEL_VARIANT_DEFAULT = "top"  # cohort_top (e.g. CHD_top, Combined_top)

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
    Get feature type metadata (binary vs numeric) from saved file in Lambda.
    
    Tries:
    1. Container filesystem (MODEL_FEATURES_PATH)
    2. Dashboard data (DASHBOARD_DATA_PATH) - fallback
    3. S3 bucket - fallback
    
    Returns:
        Dictionary mapping feature names to their types: 'binary' or 'numeric'
    """
    # Model per cohort: each cohort uses {cohort}_top (e.g. CHD_top, Combined_top)
    model_dir = f"{cohort}_top" if cohort in ("CHD", "Myocardio", "Combined") else cohort
    container_path = Path(MODEL_FEATURES_PATH) / model_dir / "feature_metadata.json"
    if not container_path.exists() and cohort != model_dir:
        container_path = Path(MODEL_FEATURES_PATH) / cohort / "feature_metadata.json"
    if container_path.exists():
        logger.info(f"Loading feature metadata from container: {container_path}")
        try:
            with open(container_path, 'r') as f:
                feature_metadata = json.load(f)
            logger.info(f"Loaded feature metadata for {len(feature_metadata)} features")
            return feature_metadata
        except Exception as e:
            logger.warning(f"Error loading feature metadata from container: {e}")
    
    # Fallback: Try dashboard data (pre-computed in dashboard_data.json)
    try:
        dashboard_data = load_dashboard_data(cohort)
        feature_metadata = dashboard_data.get("feature_metadata", {})
        if feature_metadata:
            logger.info(f"Loaded feature metadata from dashboard_data for {len(feature_metadata)} features")
            return feature_metadata
    except Exception as e:
        logger.warning(f"Error loading feature metadata from dashboard_data: {e}")
    
    # Fallback: Try S3 (if client is available); use model_dir to match container layout (e.g. CHD_top)
    if s3_client is not None:
        s3_key = f"{S3_PREFIX}/model_features/{model_dir}/feature_metadata.json"
        try:
            logger.info(f"Loading feature metadata from S3: s3://{S3_BUCKET}/{s3_key}")
            response = s3_client.get_object(Bucket=S3_BUCKET, Key=s3_key)
            feature_metadata = json.loads(response['Body'].read().decode('utf-8'))
            logger.info(f"Loaded feature metadata from S3 for {len(feature_metadata)} features")
            return feature_metadata
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchKey':
                logger.warning(f"Feature metadata not found in S3: {s3_key}")
            else:
                logger.error(f"Error loading feature metadata from S3: {e}")
        except Exception as e:
            logger.error(f"Error accessing S3: {e}")
    
    # If we get here, feature metadata not found
    logger.error(f"Feature metadata not found for cohort: {cohort}")
    return {}


def load_dashboard_data(cohort: str, model_variant: Optional[str] = None) -> Dict[str, Any]:
    """
    Load dashboard data (causal factors) for a cohort and model variant.
    
    Args:
        cohort: Base cohort name (e.g., "Combined")
        model_variant: One of base, enhanced, top, wisotzkey, FULL; default top.
    
    Tries:
    1. Container filesystem (DASHBOARD_DATA_PATH) for {cohort}_{variant}
    2. Fallback to {cohort}_top then cohort
    3. S3 bucket
    
    Model per cohort: CHD_top, CHD_base, CHD_FULL, etc.
    """
    v = (model_variant or "top").strip()
    if v.lower() == "full":
        v = "FULL"
    elif v.lower() not in ("base", "enhanced", "top", "wisotzkey"):
        v = "top"
    model_cohort = f"{cohort}_{v}"
    
    # Use model_cohort as cache key
    cache_key = model_cohort
    if cache_key in _dashboard_data_cache:
        return _dashboard_data_cache[cache_key]
    
    # Try container filesystem: {cohort}_{variant}; fallback to _top then cohort
    container_path = Path(DASHBOARD_DATA_PATH) / model_cohort / "dashboard_data.json"
    if not container_path.exists():
        container_path = Path(DASHBOARD_DATA_PATH) / f"{cohort}_top" / "dashboard_data.json"
    if not container_path.exists():
        fallback_path = Path(DASHBOARD_DATA_PATH) / cohort / "dashboard_data.json"
        if fallback_path.exists():
            logger.info(f"Using dashboard data: {fallback_path}")
            container_path = fallback_path
    if container_path.exists():
        logger.info(f"Loading dashboard data from container: {container_path}")
        with open(container_path, 'r') as f:
            data = json.load(f)
        _dashboard_data_cache[cache_key] = data
        return data
    
    # Try S3 (if client is available): variant key first, then fallback to cohort
    if s3_client is not None:
        for try_key in [f"{S3_PREFIX}/dashboard_data/{model_cohort}/dashboard_data.json",
                        f"{S3_PREFIX}/dashboard_data/{cohort}/dashboard_data.json"]:
            try:
                logger.info(f"Loading dashboard data from S3: s3://{S3_BUCKET}/{try_key}")
                response = s3_client.get_object(Bucket=S3_BUCKET, Key=try_key)
                data = json.loads(response['Body'].read().decode('utf-8'))
                _dashboard_data_cache[cache_key] = data
                return data
            except ClientError as e:
                if e.response['Error']['Code'] == 'NoSuchKey':
                    continue
                logger.error(f"Error loading dashboard data from S3: {e}")
                break
            except Exception as e:
                logger.error(f"Error accessing S3: {e}")
                break
    
    raise FileNotFoundError(f"Dashboard data not found for cohort: {model_cohort} (tried fallback {cohort})")


def load_reverse_fi_data(cohort: str, model_variant: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """
    Load Reverse Feature Importance artifacts for a model (cohort × variant).
    Returns dict with "drivers" (missed_predictions_drivers.json) and "feature_profile" (list of rows from CSV),
    or None if either file is missing (no Reverse FI for this model).
    Tries container first, then S3.
    """
    import csv
    v = (model_variant or "top").strip()
    if v.lower() == "full":
        v = "FULL"
    elif v.lower() not in ("base", "enhanced", "top", "wisotzkey"):
        v = "top"
    model_cohort = f"{cohort}_{v}"
    drivers_data = None
    profile_rows: List[Dict[str, Any]] = []
    # Try container
    for base_name in [model_cohort, f"{cohort}_top", cohort]:
        base = Path(DASHBOARD_DATA_PATH) / base_name
        drivers_path = base / "missed_predictions_drivers.json"
        profile_path = base / "missed_predictions_feature_profile.csv"
        if drivers_path.exists():
            try:
                with open(drivers_path, "r", encoding="utf-8") as f:
                    drivers_data = json.load(f)
            except Exception as e:
                logger.warning(f"Could not load Reverse FI drivers for {model_cohort}: {e}")
        if profile_path.exists():
            try:
                with open(profile_path, "r", encoding="utf-8", newline="") as f:
                    reader = csv.DictReader(f)
                    profile_rows = [dict(row) for row in reader]
            except Exception as e:
                logger.warning(f"Could not load Reverse FI feature profile for {model_cohort}: {e}")
        if drivers_data is not None or profile_rows:
            break
    # Try S3 if nothing found in container
    if drivers_data is None and not profile_rows and s3_client is not None:
        for key_prefix in [f"{S3_PREFIX}/dashboard_data/{model_cohort}", f"{S3_PREFIX}/dashboard_data/{cohort}_top", f"{S3_PREFIX}/dashboard_data/{cohort}"]:
            try:
                r = s3_client.get_object(Bucket=S3_BUCKET, Key=f"{key_prefix}/missed_predictions_drivers.json")
                drivers_data = json.loads(r["Body"].read().decode("utf-8"))
            except (ClientError, Exception):
                pass
            try:
                r = s3_client.get_object(Bucket=S3_BUCKET, Key=f"{key_prefix}/missed_predictions_feature_profile.csv")
                import io
                reader = csv.DictReader(io.StringIO(r["Body"].read().decode("utf-8")))
                profile_rows = [dict(row) for row in reader]
            except (ClientError, Exception):
                pass
            if drivers_data is not None or profile_rows:
                break
    if drivers_data is None and not profile_rows:
        return None
    return {
        "model_id": model_cohort,
        "drivers": drivers_data,
        "feature_profile": profile_rows,
    }


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


def normalize_risk_score(raw_score: float, cohort: str, method: str = "percentile", model_type: Optional[str] = None) -> Dict[str, Any]:
    """
    Normalize risk score for interpretability across cohorts.
    
    Args:
        raw_score: Raw prediction from model
        cohort: Cohort name
        method: Normalization method ("percentile" or "0-1")
        model_type: Model type used for prediction (e.g., 'catboost', 'xgboost')
    
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
    
    # Check if model type matches distribution model type
    # This is critical: CatBoost produces negative scores, XGBoost produces positive scores
    # Normalizing CatBoost scores with XGBoost distribution will give incorrect results
    dist_model_type = distribution.get('model_type', 'unknown')
    if model_type and dist_model_type != model_type:
        logger.warning(
            f"Model type mismatch for {cohort}: prediction model={model_type}, "
            f"distribution model={dist_model_type}. Skipping normalization to avoid incorrect results."
        )
        return {
            'raw_score': raw_score,
            'normalized_score': raw_score,
            'percentile': None,
            'normalization_method': 'none',
            'note': f'Model type mismatch ({model_type} vs {dist_model_type}), using raw score'
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


DEPLOYED_VARIANTS = ("base", "enhanced", "top", "wisotzkey", "FULL")


def _get_deployed_variant(cohort: str) -> str:
    """Read deployed variant for cohort from {cohort}_deployed_variant.txt. One of base, enhanced, top, wisotzkey, FULL (best by C-index then AU-PRC via compare_top_vs_wisotzkey.py --set-deployed)."""
    path = Path(MODEL_BASE_PATH) / f"{cohort}_deployed_variant.txt"
    try:
        if path.exists():
            v = path.read_text().strip()
            v_lower = v.lower()
            if v_lower in ("base", "enhanced", "top", "wisotzkey"):
                return v_lower
            if v_lower == "full":
                return "FULL"
    except Exception as e:
        logger.warning(f"Could not read deployed variant for {cohort}: {e}")
    return "top"


def _resolve_model_cohort_for_models(model_cohort: str) -> str:
    """Model per cohort: CHD_top, Myocardio_top, CHD_base, CHD_FULL, etc. If requested variant dir missing, fall back to Combined_top for legacy."""
    path = Path(MODEL_BASE_PATH) / model_cohort
    if path.exists():
        return model_cohort
    if model_cohort in ("Combined_base", "Combined_enhanced"):
        top_path = Path(MODEL_BASE_PATH) / "Combined_top"
        if top_path.exists():
            logger.info(f"Using Combined_top for missing variant {model_cohort}")
            return "Combined_top"
    return model_cohort


def load_model(cohort: str, model_type: str) -> Any:
    """
    Load a trained model for a cohort.
    
    Args:
        cohort: Cohort name (Combined_top for final workflow; CHD, Myocardio, or Combined for others)
        model_type: Model type ('catboost', 'xgboost', 'xgboost_rf')
    
    Returns:
        Loaded model object
    """
    cohort = _resolve_model_cohort_for_models(cohort)
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


def load_model_metrics(cohort: str) -> Dict[str, Any]:
    """
    Load model metrics from best_model.txt in the container (or S3 if configured).
    Returns dict with best_model, c_index, auc, au_prc, recall, metrics_text, s3_url.
    """
    if any(cohort.endswith(f"_{v}") for v in DEPLOYED_VARIANTS):
        model_cohort = cohort
    else:
        variant = _get_deployed_variant(cohort)
        model_cohort = f"{cohort}_{variant}"
    model_cohort = _resolve_model_cohort_for_models(model_cohort)
    out = {
        "best_model": None,
        "c_index": None,
        "c_index_ci": None,
        "auc": None,
        "au_prc": None,
        "recall": None,
        "metrics_text": None,
        "s3_url": os.environ.get("METRICS_S3_URL"),  # Optional: link to metrics in S3
    }
    best_model_path = Path(MODEL_BASE_PATH) / model_cohort / "best_model.txt"
    if not best_model_path.exists():
        return out
    try:
        with open(best_model_path, "r") as f:
            text = f.read()
        out["metrics_text"] = text
        for line in text.splitlines():
            if "Best Model" in line and ":" in line:
                out["best_model"] = line.split(":", 1)[1].strip()
            # New format: "  C-index: 0.62 (95% CI: [0.61, 0.64], SD: ...)"
            elif "C-index:" in line and (out["c_index"] is None or "MC-CV Mean" not in line):
                try:
                    after_colon = line.split("C-index:", 1)[-1].strip()
                    num = after_colon.replace("(", " ").split()[0]
                    out["c_index"] = float(num)
                    if "95% CI:" in line and "[" in line:
                        ci = line[line.index("["):line.index("]") + 1]
                        out["c_index_ci"] = ci
                except (ValueError, IndexError):
                    pass
            # Old format
            elif "MC-CV Mean C-index:" in line:
                try:
                    out["c_index"] = float(line.split(":", 1)[1].strip())
                except ValueError:
                    pass
            elif "MC-CV 95% CI:" in line:
                try:
                    part = line.split("MC-CV 95% CI:")[-1].strip().strip("[]")
                    out["c_index_ci"] = part
                except Exception:
                    pass
            # New format: "  Recall:  0.45 ± 0.03" or "  Recall:  N/A"
            elif line.strip().startswith("Recall:") and "MC-CV Mean" not in line:
                try:
                    after = line.split("Recall:", 1)[-1].strip()
                    if after.upper() != "N/A" and after:
                        out["recall"] = float(after.replace("±", " ").split()[0])
                except (ValueError, IndexError):
                    pass
            elif "MC-CV Mean Recall:" in line:
                try:
                    out["recall"] = float(line.split(":", 1)[1].strip().split()[0])
                except (ValueError, IndexError):
                    pass
            # New format: "  AUC:    0.62 ± 0.02" or "  AUC:     N/A"
            elif line.strip().startswith("AUC:") and "MC-CV Mean" not in line:
                try:
                    after = line.split("AUC:", 1)[-1].strip()
                    if after.upper() != "N/A" and after:
                        out["auc"] = float(after.replace("±", " ").split()[0])
                except (ValueError, IndexError):
                    pass
            elif "MC-CV Mean AUC:" in line:
                try:
                    out["auc"] = float(line.split(":", 1)[1].strip().split()[0])
                except (ValueError, IndexError):
                    pass
            # New format: "  AU-PRC:  0.35 ± 0.02" or "  AU-PRC:  N/A"
            elif "AU-PRC:" in line and "MC-CV Mean" not in line:
                try:
                    after = line.split("AU-PRC:", 1)[-1].strip()
                    if after.upper() != "N/A" and after:
                        out["au_prc"] = float(after.replace("±", " ").split()[0])
                except (ValueError, IndexError):
                    pass
            elif "MC-CV Mean AU-PRC:" in line:
                try:
                    out["au_prc"] = float(line.split(":", 1)[1].strip().split()[0])
                except (ValueError, IndexError):
                    pass
    except Exception as e:
        logger.warning(f"Error reading model metrics: {e}")
    return out


def load_all_models_performance_summary() -> List[Dict[str, Any]]:
    """
    Load metrics for every cohort × variant model present in the container.
    Returns a list of dicts: cohort, variant, best_model, c_index, c_index_ci, recall, auc, au_prc.
    """
    result = []
    base = Path(MODEL_BASE_PATH)
    for cohort in AVAILABLE_COHORTS:
        for variant in DEPLOYED_VARIANTS:
            model_cohort = f"{cohort}_{variant}"
            best_path = base / model_cohort / "best_model.txt"
            if not best_path.exists():
                continue
            m = load_model_metrics(model_cohort)
            result.append({
                "cohort": cohort,
                "variant": variant,
                "best_model": m.get("best_model"),
                "c_index": m.get("c_index"),
                "c_index_ci": m.get("c_index_ci"),
                "recall": m.get("recall"),
                "auc": m.get("auc"),
                "au_prc": m.get("au_prc"),
            })
    return result


def get_best_model(cohort: str) -> str:
    """Get the best model type for a cohort from best_model.txt."""
    cohort = _resolve_model_cohort_for_models(cohort)
    # Try container filesystem
    best_model_path = Path(MODEL_BASE_PATH) / cohort / "best_model.txt"
    if best_model_path.exists():
        with open(best_model_path, 'r') as f:
            for line in f:
                if "Best Model" in line and ":" in line:
                    best_model = line.split(":", 1)[1].strip()
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


# Model assumptions (for defaults when user does not provide values)
# Per requirements: donor ischemic time assumed < 240 min when not given; size ratio 70-200%
DONISCH_DEFAULT_MINUTES = 240.0
DONOR_RECIPIENT_RATIO_MIN_PCT = 70.0
DONOR_RECIPIENT_RATIO_MAX_PCT = 200.0

# Secondary diagnosis one-hot (Empty, None dropped; Other kept).
# Must match calculator_features.SEC_DX_LEVELS so train/test/dashboard features align.
SEC_DX_LEVELS = [
    "ARVD/C", "Dilated", "Hypertrophic", "MIXED", "Other", "Restrictive", "Unknown"
]


def _sec_dx_col(label: str) -> str:
    return f"sec_dx_{label.replace('/', '_').replace(' ', '_').strip()}"


def prepare_features_for_inference(features: Dict[str, Any]) -> Dict[str, Any]:
    """
    Prepare features for inference by creating derived variables.
    This matches the feature engineering in prepare_calculator_features().
    Applies model assumptions: DONISCH < 240 min when not given; prioritizes at-transplant over at-listing.
    
    Args:
        features: Raw feature dictionary from user input
    
    Returns:
        Dictionary with derived features added
    """
    prepared = features.copy()
    
    # Donor ischemic time (DONISCH): dichotomous per README_ready_to_run (>240 min = 1, else 0)
    # If not provided, assume <= 240 minutes (0). Otherwise convert minutes to binary.
    raw_donisch = prepared.get("donisch")
    if raw_donisch is None:
        prepared["donisch"] = 0
    else:
        try:
            minutes = float(raw_donisch)
            prepared["donisch"] = 1 if minutes > DONISCH_DEFAULT_MINUTES else 0
        except (TypeError, ValueError):
            prepared["donisch"] = 0
    
    # VAD combined (txvad OR slvad) - prioritize at transplant (txvad) over at listing (slvad)
    if "txvad" in prepared or "slvad" in prepared:
        txvad = prepared.get("txvad", 0)
        slvad = prepared.get("slvad", 0)
        prepared["vad_combined"] = 1 if (txvad == 1 or slvad == 1) else 0
    
    # Ventilation combined (txvent OR slvent OR ltxtrach OR hxtrach)
    vent_vars = ["txvent", "slvent", "ltxtrach", "hxtrach"]
    if any(v in prepared for v in vent_vars):
        vent_combined = 0
        for v in vent_vars:
            if prepared.get(v, 0) == 1:
                vent_combined = 1
                break
        prepared["vent_combined"] = vent_combined
    
    # Donor/Recipient Weight Ratio
    if "weight_donor" in prepared and "weight_txpl" in prepared:
        weight_donor = prepared.get("weight_donor")
        weight_txpl = prepared.get("weight_txpl")
        if weight_txpl and weight_txpl > 0:
            prepared["donor_weight_ratio"] = (weight_donor / weight_txpl) * 100
        else:
            prepared["donor_weight_ratio"] = None
    
    # Donor/Recipient Size Ratio (Height Ratio)
    if "height_donor" in prepared and "height_txpl" in prepared:
        height_donor = prepared.get("height_donor")
        height_txpl = prepared.get("height_txpl")
        if height_txpl and height_txpl > 0:
            prepared["donor_size_ratio"] = (height_donor / height_txpl) * 100
        else:
            prepared["donor_size_ratio"] = None
    
    # CHD Laterality Disorder (CHD_LAT) - Composite variable
    # Composite of: CHD_DEX, CHD_SI, CHD_HETER, CHD_IIVC, CHD_BIVC, CHD_LSVC, CHD_RAA, CHD_AVD
    chd_lat_vars = ["chd_dex", "chd_si", "chd_heter", "chd_iivc", "chd_bivc", "chd_lsvc", "chd_raa", "chd_avd"]
    if any(v in prepared for v in chd_lat_vars):
        chd_lat = 0
        for v in chd_lat_vars:
            if prepared.get(v, 0) == 1:
                chd_lat = 1
                break
        prepared["chd_lat"] = chd_lat
    
    # ECMO combined (if not already present)
    if "ecmo_combined" not in prepared:
        if "txecmo" in prepared or "slecmo" in prepared:
            txecmo = prepared.get("txecmo", 0)
            slecmo = prepared.get("slecmo", 0)
            prepared["ecmo_combined"] = 1 if (txecmo == 1 or slecmo == 1) else 0
    
    # eGFR calculation (if height and creatinine provided but eGFR not)
    if "egfr_tx" not in prepared and "height_txpl" in prepared and "txcreat_r" in prepared:
        height = prepared.get("height_txpl")
        creat = prepared.get("txcreat_r")
        if height and creat and creat > 0:
            prepared["egfr_tx"] = 0.413 * height / creat

    # sec_dx: one-hot from single dropdown value (e.g. "sec_dx": "Dilated" -> sec_dx_Dilated=1, others=0)
    if "sec_dx" in prepared:
        selected = prepared.pop("sec_dx")
        for level in SEC_DX_LEVELS:
            col = _sec_dx_col(level)
            if selected is not None and str(selected).strip():
                prepared[col] = 1 if (str(selected).strip().lower() == level.lower()) else 0
            else:
                prepared[col] = 0
    else:
        for level in SEC_DX_LEVELS:
            prepared[_sec_dx_col(level)] = 0

    return prepared


# Wisotzkey et al. variable set (same names as training: wisotzkey_data.WISOTZKEY_FEATURES)
WISOTZKEY_FEATURE_NAMES = [
    "CHD", "TXMCSD", "CHD_SV", "HXSURG", "HXMED", "ALBUMIN_UNDER_3", "BUN_UNDER_15",
    "eGFR_UNDER_60", "TXECMO", "YR_UNDER_2015", "WEIGHT_UNDER_75", "BMI_UNDER_18",
    "ALT_UNDER_30", "ALT_OVER_50",
]


def prepare_wisotzkey_features_for_inference(features: Dict[str, Any], cohort: str) -> Dict[str, Any]:
    """
    Build Wisotzkey-et-al. feature dict from request for inference.
    Matches wisotzkey_data.make_wisotzkey_data() definitions so the Wisotzkey model gets correct inputs.
    """
    def _num(k: str, default: float = 0.0) -> float:
        v = features.get(k)
        if v is None:
            return default
        try:
            return float(v)
        except (TypeError, ValueError):
            return default

    # CHD = 1 if Congenital HD (use cohort: CHD cohort -> 1)
    chd = 1.0 if cohort == "CHD" else 0.0
    # TXMCSD: mechanical circulatory support at transplant (txnomcsd or txmcsd)
    txmcsd = 1.0 if (_num("txnomcsd") == 1 or _num("txmcsd") == 1) else 0.0
    chd_sv = 1.0 if _num("chd_sv") == 1 else 0.0
    hxsurg = 1.0 if _num("hxsurg") == 1 else 0.0
    hxmed = 1.0 if _num("hxmed") == 1 else 0.0
    txsa = _num("txsa_r", 3.0)
    albumin_under_3 = 1.0 if txsa < 3 else 0.0
    txbun = _num("txbun_r", 15.0)
    bun_under_15 = 1.0 if txbun < 15 else 0.0
    height_cm = _num("height_txpl") * 2.54 if features.get("height_txpl") else 0.0
    creat = max(_num("txcreat_r"), 0.001)
    egfr = (0.413 * height_cm / creat) if (height_cm and creat) else 60.0
    if "egfr_tx" in features and features.get("egfr_tx") is not None:
        try:
            egfr = float(features["egfr_tx"])
        except (TypeError, ValueError):
            pass
    egfr_under_60 = 1.0 if egfr < 60 else 0.0
    txecmo = 1.0 if _num("txecmo") == 1 else 0.0
    txpl_year = _num("txpl_year", 2020.0)
    yr_under_2015 = 1.0 if txpl_year < 2015 else 0.0
    weight = _num("weight_txpl", 75.0)
    weight_under_75 = 1.0 if weight < 75 else 0.0
    height_in = _num("height_txpl", 1.0)
    bmi = (703 * weight / (height_in ** 2)) if height_in and height_in > 0 else 18.0
    bmi_under_18 = 1.0 if bmi < 18 else 0.0
    txalt = features.get("txalt") or features.get("txast")
    if txalt is not None:
        try:
            alt = float(txalt)
            alt_under_30 = 1.0 if alt < 30 else 0.0
            alt_over_50 = 1.0 if alt >= 50 else 0.0
        except (TypeError, ValueError):
            alt_under_30 = 1.0
            alt_over_50 = 0.0
    else:
        alt_under_30 = 1.0
        alt_over_50 = 0.0

    return {
        "CHD": chd,
        "TXMCSD": txmcsd,
        "CHD_SV": chd_sv,
        "HXSURG": hxsurg,
        "HXMED": hxmed,
        "ALBUMIN_UNDER_3": albumin_under_3,
        "BUN_UNDER_15": bun_under_15,
        "eGFR_UNDER_60": egfr_under_60,
        "TXECMO": txecmo,
        "YR_UNDER_2015": yr_under_2015,
        "WEIGHT_UNDER_75": weight_under_75,
        "BMI_UNDER_18": bmi_under_18,
        "ALT_UNDER_30": alt_under_30,
        "ALT_OVER_50": alt_over_50,
    }


def predict_risk_survival(
    cohort: str,
    features: Dict[str, Any],
    use_best_model_only: bool = True
) -> Dict[str, Any]:
    """
    Predict graft loss risk using survival models.
    
    Uses the model for the given cohort (CHD_top, Myocardio_top, or Combined_top).
    Each cohort has its own model and dashboard data (e.g. cohort-specific sec_dx options).
    
    Args:
        cohort: Model cohort name (e.g. CHD_top, Combined_top) or base cohort (CHD, Myocardio, Combined)
        features: Dictionary of clinical feature values
        use_best_model_only: If True, use only the best model; if False, use ensemble
    
    Returns:
        Dictionary with risk predictions and model info
    """
    if not MODEL_LIBS_AVAILABLE:
        raise RuntimeError("Model libraries not available")
    
    # Model per cohort: use deployed variant (base, enhanced, top, wisotzkey, FULL) from {cohort}_deployed_variant.txt
    if any(cohort.endswith(f"_{v}") for v in DEPLOYED_VARIANTS):
        model_cohort = _resolve_model_cohort_for_models(cohort)
        logger.info(f"Using {model_cohort} model (variant explicit)")
    elif cohort in ("CHD", "Myocardio", "Combined"):
        variant = _get_deployed_variant(cohort)
        model_cohort = _resolve_model_cohort_for_models(f"{cohort}_{variant}")
        logger.info(f"Using {model_cohort} model for cohort {cohort} (deployed variant: {variant})")
    else:
        variant = _get_deployed_variant(cohort)
        model_cohort = _resolve_model_cohort_for_models(f"{cohort}_{variant}")
        logger.info(f"Using {model_cohort} model for cohort {cohort} (deployed variant: {variant})")
    
    # Prepare features: Wisotzkey uses Wisotzkey-et-al. set; base, enhanced, top, FULL use calculator-derived
    base_cohort = cohort if cohort in ("CHD", "Myocardio", "Combined") else next(
        (model_cohort[: -len(f"_{v}")] for v in DEPLOYED_VARIANTS if model_cohort.endswith(f"_{v}")),
        "Combined"
    )
    if model_cohort.endswith("_wisotzkey"):
        prepared_features = prepare_wisotzkey_features_for_inference(features, base_cohort)
    else:
        prepared_features = prepare_features_for_inference(features)
    
    # Get best model for this cohort
    best_model_type = get_best_model(model_cohort)
    
    if use_best_model_only:
        # Use only the best model for this cohort
        model = load_model(model_cohort, best_model_type)
        
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
        
        # Prepare feature vector (use prepared features with derived variables)
        feature_vector = prepare_feature_vector(prepared_features, feature_names)
        
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
            'model_cohort': model_cohort,  # Always Combined
            'requested_cohort': cohort,  # Original cohort parameter
            'models_used': [best_model_type],
            'ensemble': False
        }
    else:
        # Use ensemble of all available models
        predictions = {}
        models_used = []
        
        for model_type in ['catboost', 'xgboost', 'xgboost_rf']:
            try:
                model = load_model(model_cohort, model_type)
                
                if model_type == 'catboost':
                    feature_names = model.feature_names_ if hasattr(model, 'feature_names_') else []
                else:
                    try:
                        feature_names = model.feature_names if hasattr(model, 'feature_names') else []
                    except:
                        feature_names = []
                
                if not feature_names:
                    # Infer from input features
                    feature_names = sorted(prepared_features.keys())
                
                feature_vector = prepare_feature_vector(prepared_features, feature_names)
                
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
            'model_cohort': model_cohort,  # Always Combined
            'requested_cohort': cohort,  # Original cohort parameter
            'models_used': models_used,
            'ensemble': True
        }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for API Gateway proxy integration.
    """
    if not event:
        return _response(400, {"error": "Empty event"})
    method = (event.get("httpMethod") or "GET").upper()
    # CORS preflight: return 200 with CORS headers immediately (before any path parsing)
    if method == "OPTIONS":
        return _response(200, {"message": "OK"})
    # Ensure logger is available and log that handler was called
    try:
        logger.info("Lambda handler invoked")
        logger.info(f"Event: {json.dumps(event)}")
    except Exception as e:
        print(f"Lambda handler invoked, but logging failed: {e}")
    try:
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
        
        # Match routes - check if path contains metadata, model-metrics, risk, or causal
        # Handle various formats: "/metadata", "/prod/metadata", "metadata", etc.
        is_metadata = ("metadata" in path_clean.lower() if path_clean else False)
        is_model_metrics = ("model-metrics" in path_clean.lower() if path_clean else False)
        is_risk = ("risk" in path_clean.lower() if path_clean else False)
        is_causal = ("causal" in path_clean.lower() if path_clean else False)
        
        # Also check if the resource directly matches
        resource_clean = resource.strip("/") if resource else ""
        if not is_metadata and not is_model_metrics and not is_risk and not is_causal:
            is_metadata = ("metadata" in resource_clean.lower() if resource_clean else False)
            is_model_metrics = ("model-metrics" in resource_clean.lower() if resource_clean else False)
            is_risk = ("risk" in resource_clean.lower() if resource_clean else False)
            is_causal = ("causal" in resource_clean.lower() if resource_clean else False)
        
        # If path is empty but we have a GET request, assume it's /metadata
        if not is_metadata and not is_model_metrics and not is_risk and not is_causal:
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
        elif method == "GET" and is_model_metrics:
            logger.info("Matched GET /model-metrics route")
            try:
                return handle_model_metrics(event)
            except Exception as e:
                logger.error(f"Error in handle_model_metrics: {e}", exc_info=True)
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
                "available_routes": ["GET /metadata", "GET /model-metrics", "POST /risk", "POST /causal"]
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


def handle_model_metrics(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    GET /model-metrics - Returns deployed model metrics (from best_model.txt in container)
    for all cohorts (CHD, Myocardio, Combined). Includes which variant (base, enhanced, top, wisotzkey, or FULL) was chosen and best algorithm, plus all standard metrics: C-index, Recall, AUC, AU-PRC.
    """
    by_cohort = {}
    for cohort in AVAILABLE_COHORTS:
        deployed_variant = _get_deployed_variant(cohort)
        m = load_model_metrics(cohort)
        by_cohort[cohort] = {
            "deployed_variant": deployed_variant,
            "best_model": m.get("best_model"),
            "c_index": m.get("c_index"),
            "c_index_ci": m.get("c_index_ci"),
            "recall": m.get("recall"),
            "auc": m.get("auc"),
            "au_prc": m.get("au_prc"),
        }
    # Performance summary for all models (all cohorts × variants present in container)
    performance_summary = load_all_models_performance_summary()
    # Default/flat view for backward compat (Combined)
    default = by_cohort.get("Combined", {})
    body = {
        "best_model": default.get("best_model"),
        "deployed_variant": default.get("deployed_variant"),
        "c_index": default.get("c_index"),
        "c_index_ci": default.get("c_index_ci"),
        "recall": default.get("recall"),
        "auc": default.get("auc"),
        "au_prc": default.get("au_prc"),
        "s3_url": load_model_metrics("Combined").get("s3_url"),
        "by_cohort": by_cohort,
        "performance_summary": performance_summary,
    }
    return _response(200, body)


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
        model_variant = query_params.get("model_variant", "top") if isinstance(query_params, dict) else "top"
        logger.info(f"Requested cohort: {cohort}, model_variant: {model_variant}")
        
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
        metrics_s3_url = os.environ.get("METRICS_S3_URL")  # Optional: dashboard tries S3 first, then API
        
        if cohort and cohort in AVAILABLE_COHORTS:
            # Load dashboard data for specific cohort and model variant
            try:
                dashboard_data = load_dashboard_data(cohort, model_variant=model_variant)
                feature_metadata = get_feature_metadata(cohort)
                feature_levels = dashboard_data.get("feature_levels", {})
                feature_level_labels = dashboard_data.get("feature_level_labels", {})
                sec_dx_dropdown_options = dashboard_data.get("sec_dx_dropdown_options", SEC_DX_LEVELS)
                sec_dx_one_hot_map = dashboard_data.get("sec_dx_one_hot_map", {lev: _sec_dx_col(lev) for lev in SEC_DX_LEVELS})
                feature_display_names = dashboard_data.get("feature_display_names", {})
                reverse_fi = load_reverse_fi_data(cohort, model_variant=model_variant)
                return _response(200, {
                    "cohort": cohort,
                    "model_variant": model_variant,
                    "available_cohorts": AVAILABLE_COHORTS,
                    "causal_factors": dashboard_data.get("top_causal_factors", []),
                    "summary": dashboard_data.get("summary", {}),
                    "aggregated_feature_importance": dashboard_data.get("aggregated_feature_importance", []),
                    "reverse_fi": reverse_fi,
                    "feature_metadata": feature_metadata,
                    "feature_levels": feature_levels,
                    "feature_level_labels": feature_level_labels,
                    "feature_display_names": feature_display_names,
                    "sec_dx_dropdown_options": sec_dx_dropdown_options,
                    "sec_dx_one_hot_map": sec_dx_one_hot_map,
                    "api_url": api_url,
                    "metrics_s3_url": metrics_s3_url
                })
            except Exception as e:
                logger.warning(f"Could not load dashboard data for {cohort}: {e}")
                # Return response even if dashboard data is missing
                return _response(200, {
                    "cohort": cohort,
                    "available_cohorts": AVAILABLE_COHORTS,
                    "causal_factors": [],
                    "summary": {},
                    "feature_display_names": {},
                    "warning": f"Dashboard data not available: {str(e)}",
                    "api_url": api_url,
                    "metrics_s3_url": metrics_s3_url
                })
        else:
            # Return all cohorts (gracefully handle missing data); include Reverse FI per model for dashboard summary
            all_causal_factors = {}
            reverse_fi_by_model: Dict[str, Any] = {}
            available_cohorts_with_data = []
            
            for c in AVAILABLE_COHORTS:
                try:
                    logger.info(f"Loading dashboard data for cohort: {c}")
                    dashboard_data = load_dashboard_data(c)
                    feature_metadata = get_feature_metadata(c)
                    feature_levels = dashboard_data.get("feature_levels", {})
                    all_causal_factors[c] = {
                        "top_causal_factors": dashboard_data.get("top_causal_factors", []),
                        "summary": dashboard_data.get("summary", {}),
                        "feature_metadata": feature_metadata,
                        "feature_levels": feature_levels,
                        "feature_level_labels": dashboard_data.get("feature_level_labels", {}),
                        "feature_display_names": dashboard_data.get("feature_display_names", {})
                    }
                    available_cohorts_with_data.append(c)
                    logger.info(f"Successfully loaded dashboard data for {c}")
                except FileNotFoundError as e:
                    logger.warning(f"Dashboard data file not found for {c}: {e}")
                    all_causal_factors[c] = {
                        "top_causal_factors": [],
                        "summary": {},
                        "error": f"Data file not found: {str(e)}"
                    }
                except Exception as e:
                    logger.error(f"Error loading dashboard data for {c}: {e}", exc_info=True)
                    all_causal_factors[c] = {
                        "top_causal_factors": [],
                        "summary": {},
                        "error": f"Error loading data: {str(e)}"
                    }
                # Load Reverse FI per model (default variant per cohort)
                try:
                    rfi = load_reverse_fi_data(c, model_variant="top")
                    if rfi:
                        reverse_fi_by_model[rfi["model_id"]] = rfi
                except Exception as e:
                    logger.debug(f"No Reverse FI for {c}: {e}")
            
            return _response(200, {
                "available_cohorts": AVAILABLE_COHORTS,
                "cohorts_with_data": available_cohorts_with_data,
                "causal_factors_by_cohort": all_causal_factors,
                "reverse_fi_by_model": reverse_fi_by_model,
                "api_url": api_url,
                "metrics_s3_url": metrics_s3_url
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
        "use_ensemble": false,  // optional, default: false (use best model only)
        "model_variant": "top"  // optional, default: "top" (single top 15 causal features model)
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
        # Use requested variant if valid, else deployed (best of base/enhanced/top/wisotzkey/FULL)
        requested = (body.get("model_variant") or "top").strip()
        if requested.lower() == "full":
            requested = "FULL"
        if requested.lower() in ("base", "enhanced", "top", "wisotzkey") or requested == "FULL":
            model_variant = requested if requested == "FULL" else requested.lower()
        else:
            model_variant = _get_deployed_variant(cohort)
        model_cohort = f"{cohort}_{model_variant}"

        # Predict risk (uses model for this cohort × variant)
        result = predict_risk_survival(model_cohort, features, use_best_model_only=not use_ensemble)
        
        # Load causal factors for this variant (fallback to _top if variant dir missing)
        try:
            dashboard_data = load_dashboard_data(cohort, model_variant=model_variant)
            top_causal = dashboard_data.get("top_causal_factors", [])
        except Exception as e:
            logger.warning(f"Could not load causal factors for {model_cohort}: {e}")
            top_causal = []
        
        # Normalize risk score for interpretability
        # Use model_cohort from result for normalization
        raw_score = result['risk_score']
        model_used = result.get('model_used', 'unknown')
        result_model_cohort = result.get('model_cohort', model_cohort)
        normalization = normalize_risk_score(raw_score, result_model_cohort, method="percentile", model_type=model_used)
        
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
        "model_variant": "top",  // optional, default: "top" (single model)
        "top_k": 10  // optional, default: 10
    }
    Default/reference values are not required; it returns causal factors and feature metadata only.
    """
    try:
        body = json.loads(event.get("body") or "{}")
        cohort = body.get("cohort", "Combined")
        model_variant = body.get("model_variant", "top")  # Single model: top 15 features
        top_k = body.get("top_k", 10)
        
        if cohort not in AVAILABLE_COHORTS:
            return _response(400, {"error": f"Invalid cohort. Must be one of: {AVAILABLE_COHORTS}"})
        
        # Load dashboard data for the specific model variant (fallback to Combined if variant dirs missing)
        dashboard_data = load_dashboard_data(cohort, model_variant=model_variant)
        top_causal = dashboard_data.get("top_causal_factors", [])[:top_k]
        
        feature_metadata = dashboard_data.get("feature_metadata", {})
        if not feature_metadata:
            feature_metadata = get_feature_metadata(cohort)
        feature_levels = dashboard_data.get("feature_levels", {})
        feature_level_labels = dashboard_data.get("feature_level_labels", {})
        sec_dx_dropdown_options = dashboard_data.get("sec_dx_dropdown_options", SEC_DX_LEVELS)
        sec_dx_one_hot_map = dashboard_data.get("sec_dx_one_hot_map", {lev: _sec_dx_col(lev) for lev in SEC_DX_LEVELS})
        return _response(200, {
            "cohort": cohort,
            "model_variant": model_variant,
            "top_causal_factors": top_causal,
            "summary": dashboard_data.get("summary", {}),
            "feature_metadata": feature_metadata,
            "feature_levels": feature_levels,
            "feature_level_labels": feature_level_labels,
            "sec_dx_dropdown_options": sec_dx_dropdown_options,
            "sec_dx_one_hot_map": sec_dx_one_hot_map
        })
    
    except Exception as e:
        import traceback
        logger.error(f"Error in handle_causal: {e}\n{traceback.format_exc()}")
        return _response(500, {"error": str(e)})
