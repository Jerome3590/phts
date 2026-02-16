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

import csv
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

# Model per cohort: deploy all variants for each cohort (copy whichever exist)
COHORTS = ["CHD", "Myocardio", "Combined"]
VARIANTS = ["_base", "_enhanced", "_top", "_wisotzkey", "_FULL"]
VALID_DEPLOYED_VARIANTS = ("base", "enhanced", "top", "wisotzkey", "FULL")


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
    
    # Copy models for each cohort × variant (base, enhanced, top, wisotzkey, FULL); Lambda uses deployed_variant.txt to choose which to run
    print("Copying models (all cohorts × variants)...")
    models_copied = 0
    for cohort in COHORTS:
        variant_dirs = [
            (MODELS_DIR / f"{cohort}{v}", lambda_models_dir / f"{cohort}{v}")
            for v in VARIANTS
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

        # Deployed variant (best of base/enhanced/top/wisotzkey/FULL by C-index then AU-PRC)
        deployed_file = MODELS_DIR / f"{cohort}_deployed_variant.txt"
        if deployed_file.exists():
            variant = deployed_file.read_text().strip()
            if variant.lower() not in (v.lower() for v in VALID_DEPLOYED_VARIANTS):
                variant = "top"
        else:
            variant = "top"
        lambda_deployed = lambda_models_dir / f"{cohort}_deployed_variant.txt"
        lambda_deployed.write_text(variant)
        print(f"  [OK] {cohort}: deployed_variant = {variant}")
    
    if models_copied == 0:
        print(f"  [WARNING] No model files found for any cohort")
    
    print(f"Total model files copied: {models_copied}")
    print()
    
    # Copy feature metadata per cohort × variant (when source exists)
    print("Copying feature metadata (all cohorts × variants when present)...")
    features_copied = 0
    for cohort in COHORTS:
        for v in VARIANTS:
            variant_name = f"{cohort}{v}"
            cohort_dashboard_dir = DASHBOARD_DIR / variant_name
            cohort_features_dir = lambda_model_features_dir / variant_name
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
                        print(f"  [OK] {variant_name}: feature_metadata.json copied ({len(feature_metadata)} features)")
                    else:
                        print(f"  [WARNING] {variant_name}: No feature_metadata in dashboard_data.json")
                except Exception as e:
                    print(f"  [ERROR] {variant_name}: Failed to extract feature_metadata: {e}")
    
    print(f"Total feature metadata files copied: {features_copied}")
    print()
    
    # Copy dashboard data for all cohorts × variants (when source exists)
    print("Copying dashboard data (all cohorts × variants when present)...")
    data_copied = 0
    for cohort in COHORTS:
        for v in VARIANTS:
            variant_name = f"{cohort}{v}"
            cohort_dashboard_dir = DASHBOARD_DIR / variant_name
            cohort_lambda_dir = lambda_dashboard_dir / variant_name
            if not cohort_dashboard_dir.exists():
                continue
            cohort_lambda_dir.mkdir(parents=True, exist_ok=True)
            dashboard_data_file = cohort_dashboard_dir / "dashboard_data.json"
            if dashboard_data_file.exists():
                with open(dashboard_data_file, "r", encoding="utf-8") as f:
                    dashboard_data = json.load(f)
                agg_path = MODELS_DIR / variant_name / "mc_cv_aggregated_feature_importance.csv"
                if agg_path.exists():
                    try:
                        with open(agg_path, "r", encoding="utf-8", newline="") as af:
                            reader = csv.DictReader(af)
                            rows = list(reader)
                        aggregated = []
                        for r in rows:
                            try:
                                aggregated.append({
                                    "feature": r.get("feature", ""),
                                    "importance_mean": float(r.get("importance_mean", 0)),
                                    "importance_std": float(r.get("importance_std", 0)),
                                })
                            except (ValueError, TypeError):
                                continue
                        dashboard_data["aggregated_feature_importance"] = aggregated
                        print(f"  [OK] {variant_name}: merged {len(aggregated)} aggregated feature importance rows")
                    except Exception as e:
                        print(f"  [WARNING] {variant_name}: could not merge aggregated feature importance: {e}")
                with open(cohort_lambda_dir / "dashboard_data.json", "w", encoding="utf-8") as f:
                    json.dump(dashboard_data, f, indent=2)
                data_copied += 1
                print(f"  [OK] {variant_name}: dashboard_data.json copied")
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
        variant_name = f"{cohort}_top"
        cohort_models = lambda_models_dir / variant_name
        if not cohort_models.exists():
            validation_errors.append(f"Models directory missing for {variant_name}")
        else:
            model_files = list(cohort_models.glob("*.cbm")) + list(cohort_models.glob("*.ubj"))
            if not model_files:
                validation_errors.append(f"No model files found for {variant_name}")
        cohort_data = lambda_dashboard_dir / variant_name / "dashboard_data.json"
        if not cohort_data.exists():
            validation_errors.append(f"Dashboard data missing for {variant_name}")
    
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
        variant_name = f"{cohort}_top"
        cohort_dir = lambda_models_dir / variant_name
        if cohort_dir.exists():
            file_count = len(list(cohort_dir.rglob('*'))) - len(list(cohort_dir.rglob('*/')))
            print(f"      {variant_name}/ ({file_count} files)")
    print(f"    model_features/")
    for cohort in COHORTS:
        variant_name = f"{cohort}_top"
        cohort_dir = lambda_model_features_dir / variant_name
        if cohort_dir.exists():
            print(f"      {variant_name}/")
    print(f"    dashboard_data/")
    for cohort in COHORTS:
        variant_name = f"{cohort}_top"
        cohort_dir = lambda_dashboard_dir / variant_name
        if cohort_dir.exists():
            print(f"      {variant_name}/")
    print(f"    risk_distributions/")
    if lambda_risk_dist_dir.exists():
        print(f"      risk_distributions.json")
    print()
    print("Next step: Build Docker image with:")
    print("  docker build -f Dockerfile.phts -t phts-risk-calculator:latest .")
    print("=" * 80)


if __name__ == "__main__":
    prepare_lambda_directory()
