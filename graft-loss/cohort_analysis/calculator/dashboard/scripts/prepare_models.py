#!/usr/bin/env python3
"""
Prepare R models for Lambda deployment.

Converts R models to Python-compatible format and uploads to S3.
"""

import argparse
import json
import boto3
import subprocess
from pathlib import Path
import pandas as pd


def convert_catboost_model(r_model_path: Path, output_path: Path):
    """Convert CatBoost R model to Python format."""
    r_script = f"""
    library(catboost)
    model <- readRDS("{r_model_path}")
    catboost.save_model(model, "{output_path}")
    """
    subprocess.run(["Rscript", "-e", r_script], check=True)
    print(f"Converted CatBoost model: {output_path}")


def convert_xgboost_model(r_model_path: Path, output_path: Path):
    """Convert XGBoost R model to Python format."""
    # XGBoost models saved as .model files are already compatible
    import shutil
    shutil.copy(r_model_path, output_path)
    print(f"Copied XGBoost model: {output_path}")


def load_model_metrics(outputs_dir: Path) -> dict:
    """Load model performance metrics from outputs."""
    metrics_file = outputs_dir / "cohort_model_cindex_mc_cv_modifiable_clinical.csv"
    
    if not metrics_file.exists():
        raise FileNotFoundError(f"Metrics file not found: {metrics_file}")
    
    df = pd.read_csv(metrics_file)
    
    # Find best model per cohort
    best_models = {}
    for cohort in ["CHD", "MyoCardio"]:
        cohort_df = df[df['Cohort'] == cohort]
        if len(cohort_df) > 0:
            best_row = cohort_df.loc[cohort_df['C_Index_Mean'].idxmax()]
            best_models[cohort] = {
                "best_model": best_row['Model'].lower().replace(' ', '_').replace('-', '_'),
                "c_index": float(best_row['C_Index_Mean']),
                "c_index_ci": [
                    float(best_row['C_Index_CI_Lower']),
                    float(best_row['C_Index_CI_Upper'])
                ]
            }
    
    return best_models


def generate_metadata(outputs_dir: Path, best_models: dict) -> dict:
    """Generate metadata JSON."""
    # Load feature information from best features file
    features_file = outputs_dir / "best_clinical_features_by_cohort_mc_cv.csv"
    
    metadata = {
        "cohorts": ["CHD", "MyoCardio"],
        "features": {},
        "models": best_models
    }
    
    # Load feature ranges from training data (simplified - would load from actual data)
    # For now, use default ranges based on feature names
    feature_categories = {
        "Kidney Function": ["txcreat_r", "lcreat_r", "hxdysdia", "hxrenins", "egfr_tx"],
        "Liver Function": ["txast", "lsast", "txalt", "lsalt", "txbili_d_r", "lsbili_d_r", 
                          "txbili_t_r", "lsbili_t_r", "hxfonlvr"],
        "Nutrition": ["txpalb_r", "lspalb_r", "txsa_r", "lssab_r", "txtp_r", "lstp_r",
                     "hxfail", "bmi_txpl", "height_txpl", "height_listing", "weight_txpl", "weight_listing"],
        "Respiratory": ["txvent", "slvent", "ltxtrach", "hxtrach"],
        "Cardiac": ["txvad", "slvad", "slnomcsd", "txecmo", "slecmo", "hxcpr", "hxshock"],
        "Immunology": ["hlatxpre", "donspac", "txfcpra", "lsfcpra"]
    }
    
    # Generate feature metadata
    for category, features in feature_categories.items():
        for feature in features:
            metadata["features"][feature] = {
                "category": category,
                "type": "numeric",
                "range": get_default_range(feature),
                "modifiability": "Modifiable" if category == "Nutrition" else "Partially Modifiable"
            }
    
    return metadata


def get_default_range(feature: str) -> list:
    """Get default range for a feature based on name patterns."""
    if "creat" in feature.lower():
        return [0.1, 10.0]
    elif "alb" in feature.lower() or "sa" in feature.lower():
        return [1.0, 5.0]
    elif "bili" in feature.lower():
        return [0.0, 20.0]
    elif "ast" in feature.lower() or "alt" in feature.lower():
        return [0.0, 500.0]
    elif "bmi" in feature.lower():
        return [10.0, 50.0]
    elif "height" in feature.lower():
        return [50.0, 200.0]  # cm
    elif "weight" in feature.lower():
        return [5.0, 150.0]  # kg
    else:
        return [0.0, 1.0]  # Binary/categorical defaults


def upload_to_s3(local_path: Path, s3_bucket: str, s3_key: str):
    """Upload file to S3."""
    s3 = boto3.client('s3')
    s3.upload_file(str(local_path), s3_bucket, s3_key)
    print(f"Uploaded {local_path} to s3://{s3_bucket}/{s3_key}")


def main():
    parser = argparse.ArgumentParser(description='Prepare models for Lambda deployment')
    parser.add_argument('--outputs-dir', type=str, default='../outputs',
                       help='Path to outputs directory')
    parser.add_argument('--models-dir', type=str, default='../models',
                       help='Path to R models directory')
    parser.add_argument('--s3-bucket', type=str, default='uva-graft-loss-cohort-models',
                       help='S3 bucket for models')
    parser.add_argument('--cohort', action='append', choices=['CHD', 'MyoCardio'],
                       help='Cohort to process (can specify multiple times)')
    
    args = parser.parse_args()
    
    outputs_dir = Path(args.outputs_dir)
    models_dir = Path(args.models_dir)
    cohorts = args.cohort or ['CHD', 'MyoCardio']
    
    # Load model metrics
    print("Loading model metrics...")
    best_models = load_model_metrics(outputs_dir)
    
    # Generate metadata
    print("Generating metadata...")
    metadata = generate_metadata(outputs_dir, best_models)
    
    # Save metadata locally
    metadata_path = Path('metadata.json')
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"Saved metadata to {metadata_path}")
    
    # Upload metadata to S3
    upload_to_s3(metadata_path, args.s3_bucket, 'models/metadata.json')
    
    # Process models for each cohort
    for cohort in cohorts:
        if cohort not in best_models:
            print(f"Warning: No best model found for {cohort}, skipping...")
            continue
        
        model_name = best_models[cohort]['best_model']
        print(f"\nProcessing {cohort} cohort with model: {model_name}")
        
        # Find R model file
        r_model_path = models_dir / cohort / f"{model_name}.rds"
        if not r_model_path.exists():
            print(f"Warning: R model not found: {r_model_path}")
            continue
        
        # Convert model
        output_path = Path(f"{cohort}_{model_name}.pkl")
        
        if 'catboost' in model_name:
            convert_catboost_model(r_model_path, output_path)
        elif 'xgboost' in model_name:
            convert_xgboost_model(r_model_path, output_path)
        else:
            print(f"Warning: Unknown model type: {model_name}")
            continue
        
        # Upload to S3
        s3_key = f"models/{cohort}/{model_name}.pkl"
        upload_to_s3(output_path, args.s3_bucket, s3_key)
        
        # Clean up local file
        output_path.unlink()
    
    print("\nModel preparation complete!")


if __name__ == "__main__":
    main()

