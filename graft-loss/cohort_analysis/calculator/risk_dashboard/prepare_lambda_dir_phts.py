#!/usr/bin/env python3
"""
Prepare Lambda directory for PHTS Docker container deployment.

This script:
1. Creates lambda_dir_phts/ directory structure
2. Copies models from outputs/models/
3. Copies dashboard data from outputs/shap_ffa/
4. Creates feature schemas
5. Validates all files are present
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
RISK_DIST_DIR = CALCULATOR_DIR / "outputs" / "risk_distributions"
LAMBDA_DIR = Path(__file__).parent / "lambda_dir_phts"

COHORTS = ["CHD", "Combined", "Myocardio"]


def prepare_lambda_directory():
    """Prepare complete Lambda directory with models and data."""
    print("=" * 80)
    print("Preparing PHTS Lambda Directory for Docker Deployment")
    print("=" * 80)
    print()
    
    # Create lambda directory structure
    lambda_models_dir = LAMBDA_DIR / "models"
    lambda_model_features_dir = LAMBDA_DIR / "model_features"
    lambda_dashboard_dir = LAMBDA_DIR / "dashboard_data"
    lambda_risk_dist_dir = LAMBDA_DIR / "risk_distributions"
    
    lambda_models_dir.mkdir(parents=True, exist_ok=True)
    lambda_model_features_dir.mkdir(parents=True, exist_ok=True)
    lambda_dashboard_dir.mkdir(parents=True, exist_ok=True)
    lambda_risk_dist_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Lambda directory: {LAMBDA_DIR}")
    print()
    
    # Copy models for each cohort (final workflow: Combined_top only for Combined; plain dir for others)
    print("Copying models...")
    models_copied = 0
    for cohort in COHORTS:
        variant_dirs = []
        if cohort == "Combined":
            variant_dirs = [
                (MODELS_DIR / f"{cohort}_top", lambda_models_dir / f"{cohort}_top"),
            ]
        else:
            variant_dirs = [
                (MODELS_DIR / cohort, lambda_models_dir / cohort),
            ]
        
        for cohort_models_dir, cohort_lambda_dir in variant_dirs:
            if not cohort_models_dir.exists():
                continue
            
            cohort_lambda_dir.mkdir(parents=True, exist_ok=True)
            
            # Copy model files
            files_copied = 0
            for model_file in cohort_models_dir.glob("*.cbm"):
                shutil.copy2(model_file, cohort_lambda_dir / model_file.name)
                files_copied += 1
            for model_file in cohort_models_dir.glob("*.ubj"):
                shutil.copy2(model_file, cohort_lambda_dir / model_file.name)
                files_copied += 1
            for model_file in cohort_models_dir.glob("best_model.txt"):
                shutil.copy2(model_file, cohort_lambda_dir / model_file.name)
                files_copied += 1
            
            # Copy JSON files
            json_dir = cohort_models_dir / "final_model_json"
            if json_dir.exists():
                json_lambda_dir = cohort_lambda_dir / "final_model_json"
                json_lambda_dir.mkdir(parents=True, exist_ok=True)
                for json_file in json_dir.glob("*.json"):
                    shutil.copy2(json_file, json_lambda_dir / json_file.name)
                    files_copied += 1
            
            if files_copied > 0:
                variant_name = cohort_lambda_dir.name
                print(f"  [OK] {variant_name}: {files_copied} files copied")
                models_copied += files_copied
    
    if models_copied == 0:
        print(f"  [WARNING] No model files found for any cohort")
    
    print(f"Total model files copied: {models_copied}")
    print()
    
    # Copy feature metadata (final workflow: Combined_top only for Combined)
    print("Copying feature metadata...")
    features_copied = 0
    for cohort in COHORTS:
        # Try variant directories first (for Combined cohort)
        variant_dirs = []
        if cohort == "Combined":
            variant_dirs = [
                (DASHBOARD_DIR / f"{cohort}_top", lambda_model_features_dir / f"{cohort}_top"),
            ]
        else:
            variant_dirs = [
                (DASHBOARD_DIR / cohort, lambda_model_features_dir / cohort),
            ]
        
        for cohort_dashboard_dir, cohort_features_dir in variant_dirs:
            if not cohort_dashboard_dir.exists():
                continue
            
            # Load dashboard_data.json to extract feature_metadata
            dashboard_data_file = cohort_dashboard_dir / "dashboard_data.json"
            if dashboard_data_file.exists():
                try:
                    with open(dashboard_data_file, 'r') as f:
                        dashboard_data = json.load(f)
                    
                    feature_metadata = dashboard_data.get("feature_metadata", {})
                    if feature_metadata:
                        # Save feature_metadata to model_features directory
                        cohort_features_dir.mkdir(parents=True, exist_ok=True)
                        
                        feature_metadata_file = cohort_features_dir / "feature_metadata.json"
                        with open(feature_metadata_file, 'w') as f:
                            json.dump(feature_metadata, f, indent=2)
                        features_copied += 1
                        variant_name = cohort_features_dir.name
                        print(f"  [OK] {variant_name}: feature_metadata.json copied ({len(feature_metadata)} features)")
                    else:
                        variant_name = cohort_features_dir.name
                        print(f"  [WARNING] {variant_name}: No feature_metadata in dashboard_data.json")
                except Exception as e:
                    variant_name = cohort_features_dir.name
                    print(f"  [ERROR] {variant_name}: Failed to extract feature_metadata: {e}")
    
    print(f"Total feature metadata files copied: {features_copied}")
    print()
    
    # Copy dashboard data
    # Handle both variant (Combined_base, Combined_enhanced) and non-variant structures
    print("Copying dashboard data...")
    data_copied = 0
    for cohort in COHORTS:
        # Try variant directories first (for Combined cohort)
        variant_dirs = []
        if cohort == "Combined":
            variant_dirs = [
                (DASHBOARD_DIR / f"{cohort}_top", lambda_dashboard_dir / f"{cohort}_top"),
            ]
        else:
            # CHD and Myocardio may not have variants, try both
            variant_dirs = [
                (DASHBOARD_DIR / cohort, lambda_dashboard_dir / cohort),
                (DASHBOARD_DIR / f"{cohort}_base", lambda_dashboard_dir / f"{cohort}_base"),
                (DASHBOARD_DIR / f"{cohort}_enhanced", lambda_dashboard_dir / f"{cohort}_enhanced")
            ]
        
        for cohort_dashboard_dir, cohort_lambda_dir in variant_dirs:
            if not cohort_dashboard_dir.exists():
                continue
            
            cohort_lambda_dir.mkdir(parents=True, exist_ok=True)
            
            # Copy dashboard_data.json
            dashboard_data_file = cohort_dashboard_dir / "dashboard_data.json"
            if dashboard_data_file.exists():
                shutil.copy2(dashboard_data_file, cohort_lambda_dir / "dashboard_data.json")
                data_copied += 1
                variant_name = cohort_lambda_dir.name
                print(f"  [OK] {variant_name}: dashboard_data.json copied")
            
            # Copy top_causal_factors.csv
            causal_factors_file = cohort_dashboard_dir / "top_causal_factors.csv"
            if causal_factors_file.exists():
                shutil.copy2(causal_factors_file, cohort_lambda_dir / "top_causal_factors.csv")
                data_copied += 1
    
    print(f"Total dashboard data files copied: {data_copied}")
    print()
    
    # Copy risk distributions
    print("Copying risk distributions...")
    risk_dist_copied = 0
    risk_dist_file = RISK_DIST_DIR / "risk_distributions.json"
    if risk_dist_file.exists():
        shutil.copy2(risk_dist_file, lambda_risk_dist_dir / "risk_distributions.json")
        risk_dist_copied += 1
        print(f"  [OK] risk_distributions.json copied")
    else:
        print(f"  [WARNING] risk_distributions.json not found at {risk_dist_file}")
    
    print(f"Total risk distribution files copied: {risk_dist_copied}")
    print()
    
    # Validate structure
    print("Validating directory structure...")
    validation_errors = []
    
    for cohort in COHORTS:
        # Check models - handle variants for Combined
        if cohort == "Combined":
            for variant in ["_top"]:
                variant_name = f"{cohort}{variant}"
                cohort_models = lambda_models_dir / variant_name
                if not cohort_models.exists():
                    validation_errors.append(f"Models directory missing for {variant_name}")
                else:
                    # Check for at least one model file
                    model_files = list(cohort_models.glob("*.cbm")) + list(cohort_models.glob("*.ubj"))
                    if not model_files:
                        validation_errors.append(f"No model files found for {variant_name}")
                
                # Check dashboard data
                cohort_data = lambda_dashboard_dir / variant_name / "dashboard_data.json"
                if not cohort_data.exists():
                    validation_errors.append(f"Dashboard data missing for {variant_name}")
        else:
            # CHD and Myocardio - check plain cohort dir only
            cohort_models = lambda_models_dir / cohort
            if not cohort_models.exists():
                validation_errors.append(f"Models directory missing for {cohort}")
            else:
                model_files = list(cohort_models.glob("*.cbm")) + list(cohort_models.glob("*.ubj"))
                if not model_files:
                    validation_errors.append(f"No model files found for {cohort}")
            cohort_data = lambda_dashboard_dir / cohort / "dashboard_data.json"
            if not cohort_data.exists():
                validation_errors.append(f"Dashboard data missing for {cohort}")
    
    if validation_errors:
        print("  [WARNING] Validation warnings:")
        for error in validation_errors:
            print(f"    - {error}")
    else:
        print("  [OK] All required files present")
    
    print()
    
    # Calculate total size
    total_size = sum(f.stat().st_size for f in LAMBDA_DIR.rglob('*') if f.is_file())
    total_size_mb = total_size / (1024 * 1024)
    
    print("=" * 80)
    print(f"Lambda directory prepared: {LAMBDA_DIR}")
    print(f"Total size: {total_size_mb:.2f} MB")
    print()
    print("Directory structure:")
    print(f"  {LAMBDA_DIR}/")
    print(f"    models/")
    for cohort in COHORTS:
        cohort_dir = lambda_models_dir / cohort
        if cohort_dir.exists():
            file_count = len(list(cohort_dir.rglob('*'))) - len(list(cohort_dir.rglob('*/')))
            print(f"      {cohort}/ ({file_count} files)")
    print(f"    model_features/")
    for cohort in COHORTS:
        cohort_dir = lambda_model_features_dir / cohort
        if cohort_dir.exists():
            print(f"      {cohort}/")
    print(f"    dashboard_data/")
    for cohort in COHORTS:
        cohort_dir = lambda_dashboard_dir / cohort
        if cohort_dir.exists():
            print(f"      {cohort}/")
    print(f"    risk_distributions/")
    if lambda_risk_dist_dir.exists():
        print(f"      risk_distributions.json")
    print()
    print("Next step: Build Docker image with:")
    print("  docker build -f Dockerfile.phts -t phts-risk-calculator:latest .")
    print("=" * 80)


if __name__ == "__main__":
    prepare_lambda_directory()
