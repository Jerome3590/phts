#!/usr/bin/env bash
# End-to-end: FFA (SHAP + Reverse FI) → Prepare Lambda dir → Deploy Lambda + API + S3
#
# Prerequisites: Models already trained (outputs/models/{cohort}_top/, etc.).
# Run from: graft-loss/cohort_analysis/calculator
#
# Usage:
#   ./run_e2e_ffa_lambda_deploy.sh              # full E2E including Lambda deploy
#   ./run_e2e_ffa_lambda_deploy.sh --no-deploy  # stop after prepare (no Docker/Lambda/S3)
#   ./run_e2e_ffa_lambda_deploy.sh --no-ffa    # skip FFA (use existing shap_ffa outputs)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALCULATOR_DIR="${CALCULATOR_DIR:-$SCRIPT_DIR}"
RISK_DASHBOARD_DIR="${CALCULATOR_DIR}/risk_dashboard"
NO_DEPLOY=false
NO_FFA=false

while [ $# -gt 0 ]; do
  case "$1" in
    --no-deploy) NO_DEPLOY=true ;;
    --no-ffa)    NO_FFA=true ;;
    -h|--help)
      echo "Usage: $0 [--no-deploy] [--no-ffa]"
      echo "  --no-deploy  Stop after prepare_lambda_dir_phts (no Docker/Lambda/S3)"
      echo "  --no-ffa     Skip SHAP/FFA+Reverse FI (use existing outputs/shap_ffa/)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

echo "=========================================="
echo "E2E: FFA + Reverse FI → Lambda deployment"
echo "=========================================="
echo "Calculator dir: ${CALCULATOR_DIR}"
echo ""

# 1) Set deployed variant per cohort (best by C-index then AU-PRC)
echo "[1/4] Setting deployed variant (compare_top_vs_wisotzkey --set-deployed)..."
cd "${CALCULATOR_DIR}"
python -m compare_top_vs_wisotzkey --set-deployed
echo ""

# 2) Run SHAP + FFA + Reverse FI per cohort (no S3 upload; we bake into Lambda)
if [ "$NO_FFA" = false ]; then
  echo "[2/4] Running SHAP + FFA + Reverse FI for all cohorts..."
  python run_shap_ffa_reverse_fi_s3.py --no-upload
  echo ""
else
  echo "[2/4] Skipping FFA (--no-ffa); using existing outputs/shap_ffa/"
  echo ""
fi

# 3) Prepare Lambda directory (models + dashboard_data including Reverse FI)
echo "[3/4] Preparing Lambda directory..."
cd "${RISK_DASHBOARD_DIR}"
python prepare_lambda_dir_phts.py
echo ""

# 4) Deploy (Docker build, push ECR, update Lambda, API Gateway, S3 HTML)
if [ "$NO_DEPLOY" = true ]; then
  echo "[4/4] Skipping deploy (--no-deploy). Run manually:"
  echo "  cd ${RISK_DASHBOARD_DIR}"
  echo "  ./deploy_complete.sh"
  exit 0
fi

echo "[4/4] Running full deployment (Docker + Lambda + API + S3)..."
./deploy_complete.sh

echo ""
echo "E2E complete: FFA (incl. Reverse FI) artifacts are in Lambda and dashboard is updated."
