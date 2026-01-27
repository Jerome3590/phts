#!/usr/bin/env python3
"""
Feature Validation Script

Validates that features used in training match features expected by the model.
This ensures consistency between training and inference.
"""

import sys
from pathlib import Path
import json
import logging
import pandas as pd
import numpy as np

# Add project paths
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
CALCULATOR_DIR = Path(__file__).parent
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(CALCULATOR_DIR))

from run_shap_ffa_workflow import prepare_calculator_features, load_calculator_data_for_shap
from train_python_models import remove_leakage_predictors

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def get_model_features(cohort: str = "Combined") -> list:
    """
    Get feature names from trained model.
    
    Args:
        cohort: Cohort name (default: Combined)
    
    Returns:
        List of feature names expected by the model
    """
    from catboost import CatBoostRegressor
    import xgboost as xgb
    
    models_dir = CALCULATOR_DIR / "outputs" / "models" / cohort
    
    # Try CatBoost first
    catboost_path = models_dir / "catboost_model.cbm"
    if catboost_path.exists():
        model = CatBoostRegressor()
        model.load_model(str(catboost_path))
        if hasattr(model, 'feature_names_'):
            return list(model.feature_names_)
    
    # Try XGBoost
    xgboost_path = models_dir / "xgboost_model.ubj"
    if xgboost_path.exists():
        model = xgb.Booster()
        model.load_model(str(xgboost_path))
        if hasattr(model, 'feature_names'):
            return list(model.feature_names)
    
    # Try XGBoost RF
    xgboost_rf_path = models_dir / "xgboost_rf_model.ubj"
    if xgboost_rf_path.exists():
        model = xgb.Booster()
        model.load_model(str(xgboost_rf_path))
        if hasattr(model, 'feature_names'):
            return list(model.feature_names)
    
    raise FileNotFoundError(f"No model found in {models_dir}")


def get_training_features(cohort: str = "Combined") -> list:
    """
    Get feature names from training data preparation.
    
    Args:
        cohort: Cohort name (default: Combined)
    
    Returns:
        List of feature names used in training
    """
    # Load and prepare data (same as training)
    df = load_calculator_data_for_shap(cohort)
    df = prepare_calculator_features(df)
    
    # Derive survival labels (simplified - just for feature extraction)
    if 'ev_time' not in df.columns:
        if 'int_dead' in df.columns and 'int_graft_loss' in df.columns:
            df['ev_time'] = df[['int_dead', 'int_graft_loss']].min(axis=1, skipna=True)
        elif 'outcome_int_graft_loss' in df.columns:
            df['ev_time'] = df['outcome_int_graft_loss']
    
    if 'ev_type' not in df.columns:
        if 'dtx_patient' in df.columns and 'graft_loss' in df.columns:
            df['ev_type'] = df[['dtx_patient', 'graft_loss']].max(axis=1, skipna=True)
        elif 'outcome_graft_loss' in df.columns:
            df['ev_type'] = df['outcome_graft_loss']
    
    if 'time' not in df.columns:
        df['time'] = df['ev_time']
    if 'status' not in df.columns:
        df['status'] = (df['ev_type'] == 1).astype(int)
    
    # Remove leakage (same as training)
    df_clean = remove_leakage_predictors(df, time_col='time', status_col='status')
    
    # Extract feature columns (exclude time, status, txpl_year)
    feature_cols = [col for col in df_clean.columns if col not in ['time', 'status', 'txpl_year']]
    
    return sorted(feature_cols)


def validate_features(cohort: str = "Combined") -> dict:
    """
    Validate that training features match model features.
    
    Args:
        cohort: Cohort name (default: Combined)
    
    Returns:
        Dictionary with validation results
    """
    logger.info(f"Validating features for cohort: {cohort}")
    
    try:
        # Get features from model
        model_features = set(get_model_features(cohort))
        logger.info(f"Model features: {len(model_features)}")
        
        # Get features from training
        training_features = set(get_training_features(cohort))
        logger.info(f"Training features: {len(training_features)}")
        
        # Compare
        missing_in_model = training_features - model_features
        missing_in_training = model_features - training_features
        common_features = model_features & training_features
        
        result = {
            'cohort': cohort,
            'model_feature_count': len(model_features),
            'training_feature_count': len(training_features),
            'common_feature_count': len(common_features),
            'missing_in_model': sorted(missing_in_model),
            'missing_in_training': sorted(missing_in_training),
            'validation_passed': len(missing_in_model) == 0 and len(missing_in_training) == 0
        }
        
        if result['validation_passed']:
            logger.info("✓ Feature validation PASSED - all features match")
        else:
            logger.warning("✗ Feature validation FAILED")
            if missing_in_model:
                logger.warning(f"  Features in training but not in model ({len(missing_in_model)}): {missing_in_model[:10]}")
            if missing_in_training:
                logger.warning(f"  Features in model but not in training ({len(missing_in_training)}): {missing_in_training[:10]}")
        
        return result
        
    except Exception as e:
        logger.error(f"Error validating features: {e}", exc_info=True)
        return {
            'cohort': cohort,
            'validation_passed': False,
            'error': str(e)
        }


def main():
    """Main validation function."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Validate features between training and model")
    parser.add_argument("--cohort", type=str, default="Combined",
                       choices=["Combined", "CHD", "Myocardio"],
                       help="Cohort to validate (default: Combined)")
    
    args = parser.parse_args()
    
    # Always validate Combined (single model for all cohorts)
    result = validate_features("Combined")
    
    # Print summary
    print("\n" + "="*80)
    print("Feature Validation Summary")
    print("="*80)
    print(f"Cohort: {result['cohort']}")
    print(f"Model features: {result.get('model_feature_count', 'N/A')}")
    print(f"Training features: {result.get('training_feature_count', 'N/A')}")
    print(f"Common features: {result.get('common_feature_count', 'N/A')}")
    print(f"Validation: {'PASSED' if result.get('validation_passed', False) else 'FAILED'}")
    
    if not result.get('validation_passed', False):
        if result.get('missing_in_model'):
            print(f"\nMissing in model ({len(result['missing_in_model'])}):")
            for f in result['missing_in_model'][:20]:
                print(f"  - {f}")
        if result.get('missing_in_training'):
            print(f"\nMissing in training ({len(result['missing_in_training'])}):")
            for f in result['missing_in_training'][:20]:
                print(f"  - {f}")
    
    # Save results
    output_file = CALCULATOR_DIR / "outputs" / "feature_validation.json"
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)
    print(f"\nResults saved to: {output_file}")
    
    return 0 if result.get('validation_passed', False) else 1


if __name__ == "__main__":
    sys.exit(main())
