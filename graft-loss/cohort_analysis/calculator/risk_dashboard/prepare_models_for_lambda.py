#!/usr/bin/env python3
"""
Prepare models and dashboard data for Lambda deployment.

This script:
1. Copies models to a deployment directory
2. Copies dashboard data (causal factors)
3. Creates a feature schema JSON for each cohort
4. Packages everything for S3 upload
"""

import json
import shutil
import sys
from pathlib import Path
from typing import Dict, List, Any

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

CALCULATOR_DIR = Path(__file__).parent.parent
MODELS_DIR = CALCULATOR_DIR / "outputs" / "models"
DASHBOARD_DIR = CALCULATOR_DIR / "outputs" / "shap_ffa"
DEPLOY_DIR = Path(__file__).parent / "lambda_deploy"

COHORTS = ["CHD", "Combined", "Myocardio"]


def load_feature_names_from_model(cohort: str, model_type: str) -> List[str]:
    """Load feature names from a trained model."""
    try:
        if model_type == 'catboost':
            from catboost import CatBoostRegressor
            model_path = MODELS_DIR / cohort / "catboost_model.cbm"
            if model_path.exists():
                model = CatBoostRegressor()
                model.load_model(str(model_path))
                return model.feature_names_ if hasattr(model, 'feature_names_') else []
        elif model_type in ['xgboost', 'xgboost_rf']:
            import xgboost as xgb
            model_filename = "xgboost_model.ubj" if model_type == 'xgboost' else "xgboost_rf_model.ubj"
            model_path = MODELS_DIR / cohort / model_filename
            if model_path.exists():
                model = xgb.Booster()
                model.load_model(str(model_path))
                return model.feature_names if hasattr(model, 'feature_names') else []
    except Exception as e:
        print(f"Warning: Could not load feature names from {cohort}/{model_type}: {e}")
    
    return []


def create_feature_schema(cohort: str) -> Dict[str, Any]:
    """Create feature schema JSON for a cohort."""
    # Try to get feature names from best model
    best_model_path = MODELS_DIR / cohort / "best_model.txt"
    best_model_type = "xgboost"  # default
    
    if best_model_path.exists():
        with open(best_model_path, 'r') as f:
            for line in f:
                if line.startswith("Best Model:"):
                    best_model = line.split("Best Model:")[1].strip()
                    if "XGBoost RF" in best_model:
                        best_model_type = "xgboost_rf"
                    elif "XGBoost" in best_model:
                        best_model_type = "xgboost"
                    elif "CatBoost" in best_model:
                        best_model_type = "catboost"
                    break
    
    feature_names = load_feature_names_from_model(cohort, best_model_type)
    
    # If feature names not available, try other models
    if not feature_names:
        for model_type in ['catboost', 'xgboost', 'xgboost_rf']:
            feature_names = load_feature_names_from_model(cohort, model_type)
            if feature_names:
                break
    
    # Create schema
    schema = {
        "cohort": cohort,
        "best_model": best_model_type,
        "feature_names": feature_names,
        "feature_count": len(feature_names),
        "features": {}
    }
    
    # Add feature metadata (if available from dashboard data)
    dashboard_data_path = DASHBOARD_DIR / cohort / "dashboard_data.json"
    if dashboard_data_path.exists():
        with open(dashboard_data_path, 'r') as f:
            dashboard_data = json.load(f)
            top_factors = dashboard_data.get("top_causal_factors", [])
            
            # Create feature metadata
            for factor in top_factors:
                feature_name = factor.get("feature")
                if feature_name:
                    schema["features"][feature_name] = {
                        "importance": factor.get("causal_responsibility", factor.get("importance", 0)),
                        "shap_importance": factor.get("shap_importance", 0),
                        "is_top_factor": True
                    }
    
    return schema


def prepare_deployment():
    """Prepare all files for Lambda deployment."""
    print("Preparing models and data for Lambda deployment...")
    
    # Create deployment directory
    DEPLOY_DIR.mkdir(parents=True, exist_ok=True)
    
    # Copy models
    models_deploy_dir = DEPLOY_DIR / "models"
    models_deploy_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Copying models from {MODELS_DIR}...")
    for cohort in COHORTS:
        cohort_models_dir = MODELS_DIR / cohort
        if cohort_models_dir.exists():
            cohort_deploy_dir = models_deploy_dir / cohort
            cohort_deploy_dir.mkdir(parents=True, exist_ok=True)
            
            # Copy model files
            for model_file in cohort_models_dir.glob("*.cbm"):
                shutil.copy2(model_file, cohort_deploy_dir / model_file.name)
            for model_file in cohort_models_dir.glob("*.ubj"):
                shutil.copy2(model_file, cohort_deploy_dir / model_file.name)
            for model_file in cohort_models_dir.glob("best_model.txt"):
                shutil.copy2(model_file, cohort_deploy_dir / model_file.name)
            
            # Copy JSON files
            json_dir = cohort_models_dir / "final_model_json"
            if json_dir.exists():
                json_deploy_dir = cohort_deploy_dir / "final_model_json"
                json_deploy_dir.mkdir(parents=True, exist_ok=True)
                for json_file in json_dir.glob("*.json"):
                    shutil.copy2(json_file, json_deploy_dir / json_file.name)
            
            print(f"  ✓ Copied models for {cohort}")
    
    # Copy dashboard data
    dashboard_deploy_dir = DEPLOY_DIR / "dashboard_data"
    dashboard_deploy_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Copying dashboard data from {DASHBOARD_DIR}...")
    for cohort in COHORTS:
        cohort_dashboard_dir = DASHBOARD_DIR / cohort
        if cohort_dashboard_dir.exists():
            cohort_deploy_dir = dashboard_deploy_dir / cohort
            cohort_deploy_dir.mkdir(parents=True, exist_ok=True)
            
            # Copy dashboard_data.json
            dashboard_data_file = cohort_dashboard_dir / "dashboard_data.json"
            if dashboard_data_file.exists():
                shutil.copy2(dashboard_data_file, cohort_deploy_dir / "dashboard_data.json")
            
            # Copy top_causal_factors.csv
            causal_factors_file = cohort_dashboard_dir / "top_causal_factors.csv"
            if causal_factors_file.exists():
                shutil.copy2(causal_factors_file, cohort_deploy_dir / "top_causal_factors.csv")
            
            print(f"  ✓ Copied dashboard data for {cohort}")
    
    # Create feature schemas
    schemas_dir = DEPLOY_DIR / "schemas"
    schemas_dir.mkdir(parents=True, exist_ok=True)
    
    print("Creating feature schemas...")
    for cohort in COHORTS:
        schema = create_feature_schema(cohort)
        schema_path = schemas_dir / f"{cohort}_feature_schema.json"
        with open(schema_path, 'w') as f:
            json.dump(schema, f, indent=2)
        print(f"  ✓ Created schema for {cohort} ({schema['feature_count']} features)")
    
    print(f"\nDeployment package ready at: {DEPLOY_DIR}")
    print("\nNext steps:")
    print(f"1. Upload to S3: aws s3 sync {DEPLOY_DIR}/ s3://your-bucket/")
    print(f"2. Or package for Lambda: cd {DEPLOY_DIR} && zip -r lambda-package.zip .")


if __name__ == "__main__":
    prepare_deployment()
