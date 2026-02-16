#!/usr/bin/env python3
"""
SHAP + FFA + Reverse Feature Importance workflow (local or S3).

Run after model training and performance metrics. Runs run_shap_ffa_workflow.py
per cohort (SHAP, FFA, Reverse FI), saves to outputs/shap_ffa/{cohort}_top/,
and optionally uploads to S3. Same artifact list as prepare_lambda_dir_phts.py.

Usage (CLI):
  python run_shap_ffa_reverse_fi_s3.py
  python run_shap_ffa_reverse_fi_s3.py --no-upload
  python run_shap_ffa_reverse_fi_s3.py --cohort CHD --cohort Combined

Interactive (VS Code / Jupyter): Use # %% cells below; edit config in cell 1, then Run Cell / Run All.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

# Resolve calculator directory (script lives in cohort_analysis/calculator)
SCRIPT_DIR = Path(__file__).resolve().parent
CALCULATOR_DIR = SCRIPT_DIR

# Same artifacts as prepare_lambda_dir_phts.py (keep in sync for build/deploy)
ARTIFACTS = [
    "dashboard_data.json",
    "missed_predictions_drivers.json",
    "missed_predictions_feature_profile.csv",
    "missed_predictions_feature_profile.parquet",
    "ffa_causal_factors.csv",
    "top_causal_factors.csv",
    "combined_shap_importance.csv",
]

DEFAULT_COHORTS = ["CHD", "Myocardio", "Combined"]
DEFAULT_TOP_K = 15
MODEL_VARIANT = "top"


def run_workflow(cohorts, top_k, upload_to_s3, s3_bucket, s3_prefix):
    """Run SHAP+FFA+Reverse FI per cohort and optionally upload to S3."""
    workflow_script = CALCULATOR_DIR / "run_shap_ffa_workflow.py"
    if not workflow_script.exists():
        print(f"Error: {workflow_script} not found.", file=sys.stderr)
        return

    print("=" * 60)
    print("SHAP + FFA + Reverse Feature Importance (local workflow)")
    print("=" * 60)
    print(f"Calculator dir: {CALCULATOR_DIR}")
    print(f"Cohorts: {cohorts}")
    print(f"Top-K: {top_k}")
    print(f"Upload to S3: {upload_to_s3}")
    if upload_to_s3:
        print(f"S3: s3://{s3_bucket}/{s3_prefix}/dashboard_data/")
    print()

    for cohort in cohorts:
        model_cohort = f"{cohort}_{MODEL_VARIANT}"
        print("=" * 60)
        print(f"Running SHAP + FFA + Reverse FI for {cohort} ({model_cohort})")
        print("=" * 60)
        result = subprocess.run(
            [
                sys.executable,
                str(workflow_script),
                "--cohort",
                cohort,
                "--model-variant",
                MODEL_VARIANT,
                "--top-k",
                str(top_k),
            ],
            cwd=str(CALCULATOR_DIR),
        )
        if result.returncode != 0:
            print(f"Warning: workflow for {cohort} exited with code {result.returncode}", file=sys.stderr)
        else:
            print(f"Done: {model_cohort}")
        print()

    print("Local outputs: outputs/shap_ffa/{cohort}_top/")
    print()

    if not upload_to_s3:
        print("S3 upload skipped.")
        return

    try:
        import boto3
        s3 = boto3.client("s3")
    except Exception as e:
        print(f"S3 upload skipped: {e}")
        return

    base = CALCULATOR_DIR / "outputs" / "shap_ffa"
    uploaded = 0
    for cohort in cohorts:
        model_cohort = f"{cohort}_{MODEL_VARIANT}"
        local_dir = base / model_cohort
        s3_prefix_key = f"{s3_prefix}/dashboard_data/{model_cohort}"
        for fname in ARTIFACTS:
            path = local_dir / fname
            if path.exists():
                key = f"{s3_prefix_key}/{fname}"
                try:
                    s3.upload_file(str(path), s3_bucket, key)
                    print(f"  Uploaded: s3://{s3_bucket}/{key}")
                    uploaded += 1
                except Exception as e:
                    print(f"  Failed {key}: {e}", file=sys.stderr)

    print(f"\nUploaded {uploaded} file(s) to s3://{s3_bucket}/{s3_prefix}/dashboard_data/")


def main():
    parser = argparse.ArgumentParser(
        description="Run SHAP + FFA + Reverse FI per cohort, optionally upload to S3.",
        epilog="Outputs: outputs/shap_ffa/{cohort}_top/. Use prepare_lambda_dir_phts.py after for Lambda dir.",
    )
    parser.add_argument(
        "--cohort",
        action="append",
        dest="cohorts",
        metavar="COHORT",
        help=f"Cohort to run (repeat for multiple). Default: {', '.join(DEFAULT_COHORTS)}",
    )
    parser.add_argument(
        "--no-upload",
        action="store_true",
        help="Only run workflow locally; do not upload to S3.",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=DEFAULT_TOP_K,
        metavar="K",
        help=f"Top K causal factors (default: {DEFAULT_TOP_K}).",
    )
    parser.add_argument(
        "--s3-bucket",
        default=os.environ.get("PHTS_BUCKET", "jerome-dixon.io"),
        help="S3 bucket (default: PHTS_BUCKET or jerome-dixon.io).",
    )
    parser.add_argument(
        "--s3-prefix",
        default=os.environ.get("S3_PREFIX", "uva/phts-risk-calculator"),
        help="S3 prefix (default: S3_PREFIX or uva/phts-risk-calculator).",
    )
    args = parser.parse_args()

    cohorts = args.cohorts if args.cohorts else DEFAULT_COHORTS
    run_workflow(
        cohorts=cohorts,
        top_k=args.top_k,
        upload_to_s3=not args.no_upload,
        s3_bucket=args.s3_bucket,
        s3_prefix=args.s3_prefix,
    )


# %% [markdown]
# ## Configuration (edit and run this cell first)
# Set cohorts, top-k, and whether to upload to S3. Then run the next cell.

# %%
if __name__ == "__main__" and len(sys.argv) <= 1:
    # Interactive config: edit and run this cell, then run the cell below.
    COHORTS = ["CHD", "Myocardio", "Combined"]
    TOP_K = 15
    UPLOAD_TO_S3 = True
    S3_BUCKET = os.environ.get("PHTS_BUCKET", "jerome-dixon.io")
    S3_PREFIX = os.environ.get("S3_PREFIX", "uva/phts-risk-calculator")

# %%
if __name__ == "__main__" and len(sys.argv) <= 1:
    # Run SHAP + FFA + Reverse FI (uses COHORTS, TOP_K, UPLOAD_TO_S3, S3_* from above).
    run_workflow(
        cohorts=COHORTS,
        top_k=TOP_K,
        upload_to_s3=UPLOAD_TO_S3,
        s3_bucket=S3_BUCKET,
        s3_prefix=S3_PREFIX,
    )

# %%
if __name__ == "__main__":
    # CLI: when invoked with args, parse and run.
    if len(sys.argv) > 1:
        main()
