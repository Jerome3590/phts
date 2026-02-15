#!/usr/bin/env python3
"""
Compare top-15 causal feature models vs Wisotzkey-vars models across cohorts.

Reads MC-CV metrics and best_model.txt from:
  outputs/models/{cohort}_top/
  outputs/models/{cohort}_wisotzkey/
and prints a side-by-side comparison (C-index, Recall, AUC, AU-PRC, best model type).

Best-model-chosen logic: per cohort, the deployed model is the variant (top or wisotzkey)
with higher C-index (then AU-PRC tiebreaker). Use --set-deployed to write
{cohort}_deployed_variant.txt so Lambda/dashboard use the chosen variant.

Usage:
  python compare_top_vs_wisotzkey.py
  python compare_top_vs_wisotzkey.py --output comparison.csv
  python compare_top_vs_wisotzkey.py --set-deployed   # write deployed_variant per cohort
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

# Calculator dir
CALCULATOR_DIR = Path(__file__).parent
MODELS_DIR = CALCULATOR_DIR / "outputs" / "models"
COHORTS = ["CHD", "Myocardio", "Combined"]
VARIANTS = ["_top", "_wisotzkey"]


def load_best_model_name(cohort_dir: Path) -> str:
    """Read best model type from best_model.txt."""
    best_path = cohort_dir / "best_model.txt"
    if not best_path.exists():
        return "—"
    text = best_path.read_text()
    for line in text.splitlines():
        if line.strip().startswith("Best Model") and ":" in line:
            return line.split(":", 1)[1].strip()
    return "—"


def load_mc_cv_metrics(cohort_dir: Path):
    """Load mc_cv_model_metrics.csv if present."""
    path = cohort_dir / "mc_cv_model_metrics.csv"
    if not path.exists():
        return None
    return pd.read_csv(path)


def get_best_row_metrics(metrics_df: pd.DataFrame) -> dict:
    """Get C-index, Recall, AUC, AU-PRC for the best model (max C-index)."""
    if metrics_df is None or metrics_df.empty:
        return {}
    if "C_Index_Mean" not in metrics_df.columns:
        return {}
    best_idx = metrics_df["C_Index_Mean"].idxmax()
    row = metrics_df.loc[best_idx]
    out = {
        "C_Index_Mean": row.get("C_Index_Mean"),
        "C_Index_CI_Lower": row.get("C_Index_CI_Lower"),
        "C_Index_CI_Upper": row.get("C_Index_CI_Upper"),
        "Recall_Mean": row.get("Recall_Mean"),
        "AUC_Mean": row.get("AUC_Mean"),
        "AU_PRC_Mean": row.get("AU_PRC_Mean"),
    }
    return out


def main():
    parser = argparse.ArgumentParser(
        description="Compare top-15 vs Wisotzkey model sets (MC-CV metrics and best model)."
    )
    parser.add_argument(
        "--output", "-o", type=str, default=None,
        help="Optional path to write comparison CSV",
    )
    parser.add_argument(
        "--models-dir", type=str, default=None,
        help=f"Override models directory (default: {MODELS_DIR})",
    )
    parser.add_argument(
        "--set-deployed", action="store_true",
        help="Write {cohort}_deployed_variant.txt (top or wisotzkey) per cohort for deployment",
    )
    args = parser.parse_args()
    models_dir = Path(args.models_dir) if args.models_dir else MODELS_DIR

    if not models_dir.exists():
        print(f"Models directory not found: {models_dir}", file=sys.stderr)
        print("Train both sets first, e.g.:", file=sys.stderr)
        print("  python train_python_models.py --cohort CHD --top_features_only", file=sys.stderr)
        print("  python train_python_models.py --cohort CHD --wisotzkey_vars_only", file=sys.stderr)
        sys.exit(1)

    rows = []
    for cohort in COHORTS:
        for variant in VARIANTS:
            name = f"{cohort}{variant}"
            cohort_dir = models_dir / name
            if not cohort_dir.exists():
                rows.append({
                    "cohort": cohort,
                    "variant": name,
                    "best_model": "—",
                    "C_Index_Mean": None,
                    "C_Index_CI": None,
                    "AUC_Mean": None,
                    "AU_PRC_Mean": None,
                    "Recall_Mean": None,
                })
                continue
            metrics_df = load_mc_cv_metrics(cohort_dir)
            best_name = load_best_model_name(cohort_dir)
            m = get_best_row_metrics(metrics_df)
            ci_lo = m.get("C_Index_CI_Lower")
            ci_hi = m.get("C_Index_CI_Upper")
            try:
                ci_str = f"[{float(ci_lo):.4f}, {float(ci_hi):.4f}]" if ci_lo is not None and ci_hi is not None else ""
            except (TypeError, ValueError):
                ci_str = ""
            rows.append({
                "cohort": cohort,
                "variant": name,
                "best_model": best_name,
                "C_Index_Mean": m.get("C_Index_Mean"),
                "C_Index_CI": ci_str,
                "AUC_Mean": m.get("AUC_Mean"),
                "AU_PRC_Mean": m.get("AU_PRC_Mean"),
                "Recall_Mean": m.get("Recall_Mean"),
            })

    df = pd.DataFrame(rows)

    # Print table
    print("=" * 100)
    print("Comparison: Top-15 causal feature models vs Wisotzkey-vars models")
    print("=" * 100)
    for cohort in COHORTS:
        sub = df[df["cohort"] == cohort]
        print(f"\n{cohort}:")
        for _, r in sub.iterrows():
            c = r["C_Index_Mean"]
            c_str = f"{c:.4f}" if pd.notna(c) and c is not None else "—"
            auc = r["AUC_Mean"]
            auc_str = f"{auc:.4f}" if pd.notna(auc) and auc is not None else "—"
            auprc = r["AU_PRC_Mean"]
            auprc_str = f"{auprc:.4f}" if pd.notna(auprc) and auprc is not None else "—"
            rec = r["Recall_Mean"]
            rec_str = f"{rec:.4f}" if pd.notna(rec) and rec is not None else "—"
            print(f"  {r['variant']:25}  best={r['best_model']:12}  C-index={c_str:8}  Recall={rec_str:8}  AUC={auc_str:8}  AU-PRC={auprc_str:8}")
    print()

    if args.output:
        out_path = Path(args.output)
        df.to_csv(out_path, index=False)
        print(f"Wrote {out_path}")

    if args.set_deployed:
        for cohort in COHORTS:
            top_dir = models_dir / f"{cohort}_top"
            wis_dir = models_dir / f"{cohort}_wisotzkey"
            top_metrics = load_mc_cv_metrics(top_dir) if top_dir.exists() else None
            wis_metrics = load_mc_cv_metrics(wis_dir) if wis_dir.exists() else None
            top_best = get_best_row_metrics(top_metrics) if top_metrics is not None else {}
            wis_best = get_best_row_metrics(wis_metrics) if wis_metrics is not None else {}
            top_c = top_best.get("C_Index_Mean")
            wis_c = wis_best.get("C_Index_Mean")
            top_c = float(top_c) if top_c is not None and pd.notna(top_c) else None
            wis_c = float(wis_c) if wis_c is not None and pd.notna(wis_c) else None
            if top_c is None and wis_c is None:
                variant = "top"
                print(f"  [WARN] {cohort}: no metrics for top or wisotzkey; defaulting to top")
            elif wis_c is None or (top_c is not None and top_c >= wis_c):
                if top_c is not None and wis_c is not None and top_c == wis_c:
                    top_au = top_best.get("AU_PRC_Mean")
                    wis_au = wis_best.get("AU_PRC_Mean")
                    if wis_au is not None and (top_au is None or (wis_au is not None and float(wis_au) > float(top_au))):
                        variant = "wisotzkey"
                    else:
                        variant = "top"
                else:
                    variant = "top"
            else:
                variant = "wisotzkey"
            out_file = models_dir / f"{cohort}_deployed_variant.txt"
            out_file.write_text(variant.strip())
            print(f"  [OK] {cohort}: deployed variant = {variant} -> {out_file.name}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
