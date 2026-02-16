#!/usr/bin/env python3
"""
End-to-end: FFA (SHAP + Reverse FI) → Prepare Lambda dir → Deploy Lambda + API + S3.

Prerequisites: Models already trained (outputs/models/{cohort}_top/, etc.).
Run from: graft-loss/cohort_analysis/calculator

Usage:
  python run_e2e_ffa_lambda_deploy.py              # full E2E including Lambda deploy
  python run_e2e_ffa_lambda_deploy.py --no-deploy  # stop after prepare (no Docker/Lambda/S3)
  python run_e2e_ffa_lambda_deploy.py --no-ffa    # skip FFA (use existing shap_ffa outputs)
"""

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CALCULATOR_DIR = SCRIPT_DIR
RISK_DASHBOARD_DIR = CALCULATOR_DIR / "risk_dashboard"


def _which(name):
    """Return path to executable if found in PATH, else None."""
    import shutil
    return shutil.which(name)


def run(cmd, cwd=None, check=True):
    cwd = str(cwd or CALCULATOR_DIR)
    print(f"  $ {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd)
    if check and result.returncode != 0:
        sys.exit(result.returncode)
    return result.returncode


def main():
    ap = argparse.ArgumentParser(
        description="E2E: FFA + Reverse FI → prepare Lambda dir → (optional) deploy Lambda + API + S3.",
    )
    ap.add_argument("--no-deploy", action="store_true", help="Stop after prepare; do not run deploy_complete.sh")
    ap.add_argument("--no-ffa", action="store_true", help="Skip SHAP/FFA+Reverse FI; use existing outputs/shap_ffa/")
    args = ap.parse_args()

    print("=" * 60)
    print("E2E: FFA + Reverse FI → Lambda deployment")
    print("=" * 60)
    print(f"Calculator dir: {CALCULATOR_DIR}")
    print()

    # 1) Set deployed variant
    print("[1/4] Setting deployed variant (compare_top_vs_wisotzkey --set-deployed)...")
    run([sys.executable, "-m", "compare_top_vs_wisotzkey", "--set-deployed"])
    print()

    # 2) SHAP + FFA + Reverse FI
    if not args.no_ffa:
        print("[2/4] Running SHAP + FFA + Reverse FI for all cohorts...")
        run([sys.executable, str(CALCULATOR_DIR / "run_shap_ffa_reverse_fi_s3.py"), "--no-upload"])
        print()
    else:
        print("[2/4] Skipping FFA (--no-ffa); using existing outputs/shap_ffa/")
        print()

    # 3) Prepare Lambda directory
    print("[3/4] Preparing Lambda directory...")
    prepare_script = RISK_DASHBOARD_DIR / "prepare_lambda_dir_phts.py"
    if not prepare_script.exists():
        print(f"Error: {prepare_script} not found.", file=sys.stderr)
        sys.exit(1)
    run([sys.executable, str(prepare_script)], cwd=RISK_DASHBOARD_DIR)
    print()

    # 4) Deploy
    if args.no_deploy:
        print("[4/4] Skipping deploy (--no-deploy). Run manually:")
        print(f"  cd {RISK_DASHBOARD_DIR}")
        print("  ./deploy_complete.sh   # or: bash deploy_complete.sh")
        return

    print("[4/4] Running full deployment (Docker + Lambda + API + S3)...")
    deploy_script = RISK_DASHBOARD_DIR / "deploy_complete.sh"
    if not deploy_script.exists():
        print(f"Error: {deploy_script} not found. Run from calculator dir.", file=sys.stderr)
        sys.exit(1)
    if sys.platform == "win32" and not _which("bash"):
        print("[4/4] On Windows, run deployment manually (bash required for deploy_complete.sh):")
        print(f"  cd {RISK_DASHBOARD_DIR}")
        print("  bash deploy_complete.sh")
        return
    cmd = ["bash", str(deploy_script)] if sys.platform == "win32" else [str(deploy_script)]
    run(cmd, cwd=RISK_DASHBOARD_DIR)

    print()
    print("E2E complete: FFA (incl. Reverse FI) artifacts are in Lambda and dashboard is updated.")


if __name__ == "__main__":
    main()
