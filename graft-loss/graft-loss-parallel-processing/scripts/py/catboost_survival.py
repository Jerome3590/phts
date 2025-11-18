#!/usr/bin/env python3
import argparse
import json
import os
import sys
import pandas as pd
import numpy as np
from pathlib import Path

try:
    from catboost import CatBoostRegressor, Pool
except Exception as e:
    print("ERROR: Failed to import catboost. Install with: pip install catboost", file=sys.stderr)
    raise


def parse_args():
    p = argparse.ArgumentParser(description="Train CatBoost survival-like model using signed-time labels.")
    p.add_argument("--train", required=True, help="CSV with training data")
    p.add_argument("--test", required=True, help="CSV with test data")
    p.add_argument("--time-col", required=True)
    p.add_argument("--status-col", required=True)
    p.add_argument("--outdir", required=True, help="Output directory for artifacts")
    p.add_argument("--cat-cols", default=None, help="Comma-separated list of categorical columns")
    p.add_argument("--model-file", default="catboost_model.cbm")
    p.add_argument("--pred-file", default="catboost_predictions.csv")
    p.add_argument("--imp-file", default="catboost_importance.csv")
    return p.parse_args()


def make_signed_time_label(df: pd.DataFrame, time_col: str, status_col: str) -> np.ndarray:
    time = pd.to_numeric(df[time_col], errors="coerce").astype(float)
    status = pd.to_numeric(df[status_col], errors="coerce").astype(int)
    # ensure strictly positive times
    time = np.where(np.isfinite(time) & (time <= 0), np.finfo(float).eps, time)
    # signed-time: positive for events, negative for censored
    label = np.where(status == 1, time, -time)
    # filter invalid
    mask = np.isfinite(label) & (label != 0)
    return label, mask


def main():
    args = parse_args()
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    train = pd.read_csv(args.train)
    test = pd.read_csv(args.test)

    y_train, m_train = make_signed_time_label(train, args.time_col, args.status_col)
    y_test, m_test = make_signed_time_label(test, args.time_col, args.status_col)

    X_train = train.loc[m_train].copy()
    X_test = test.loc[m_test].copy()
    y_train = y_train[m_train]
    y_test = y_test[m_test]

    # Drop non-feature columns
    drop_cols = [args.time_col, args.status_col]
    X_train = X_train.drop(columns=[c for c in drop_cols if c in X_train.columns])
    X_test = X_test.drop(columns=[c for c in drop_cols if c in X_test.columns])

    print(f"DEBUG: After dropping time/status columns:")
    print(f"  X_train shape: {X_train.shape}")
    print(f"  X_test shape: {X_test.shape}")
    print(f"  X_train columns: {list(X_train.columns)}")
    print(f"  X_test columns: {list(X_test.columns)}")

    # Detect categorical columns
    if args.cat_cols:
        cat_cols = [c for c in args.cat_cols.split(',') if c in X_train.columns]
        print(f"DEBUG: Using provided categorical columns: {cat_cols}")
    else:
        # heuristic: object or category dtype
        cat_cols = [c for c in X_train.columns if X_train[c].dtype == object or str(X_train[c].dtype).startswith('category')]
        print(f"DEBUG: Auto-detected categorical columns: {cat_cols}")

    # Align columns
    common_cols = [c for c in X_train.columns if c in X_test.columns]
    X_train = X_train[common_cols]
    X_test = X_test[common_cols]
    
    print(f"DEBUG: After column alignment:")
    print(f"  Common columns: {len(common_cols)}")
    print(f"  Final feature columns: {list(common_cols)}")
    
    # Check for dropped columns
    train_only = [c for c in X_train.columns if c not in X_test.columns]
    test_only = [c for c in X_test.columns if c not in X_train.columns]
    if train_only:
        print(f"WARNING: Train-only columns (will be dropped): {train_only}")
    if test_only:
        print(f"WARNING: Test-only columns (will be dropped): {test_only}")

    cat_idx = [i for i, c in enumerate(common_cols) if c in cat_cols]

    params = dict(
        loss_function='RMSE',  # using signed-time label as proxy target
        depth=6,
        learning_rate=0.05,
        iterations=2000,
        l2_leaf_reg=3.0,
        random_seed=42,
        verbose=200,
        allow_writing_files=False,
    )

    train_pool = Pool(X_train, label=y_train, cat_features=cat_idx)
    test_pool = Pool(X_test, label=y_test, cat_features=cat_idx)

    model = CatBoostRegressor(**params)
    model.fit(train_pool, eval_set=test_pool, use_best_model=True)

    # Predictions (risk scores proxy): larger -> higher risk (use negative prediction if desired)
    preds = model.predict(test_pool)

    # Feature importance
    imp = model.get_feature_importance(train_pool, type='FeatureImportance')
    imp_df = pd.DataFrame({
        'feature': common_cols,
        'importance': imp
    }).sort_values('importance', ascending=False)

    # Save artifacts
    model_path = outdir / args.model_file
    pred_path = outdir / args.pred_file
    imp_path = outdir / args.imp_file

    model.save_model(str(model_path))
    pd.DataFrame({'prediction': preds}).to_csv(pred_path, index=False)
    imp_df.to_csv(imp_path, index=False)

    # Emit a small JSON summary for the R caller
    summary = {
        'model_file': str(model_path),
        'pred_file': str(pred_path),
        'imp_file': str(imp_path),
        'n_train': int(X_train.shape[0]),
        'n_test': int(X_test.shape[0]),
        'n_features': int(X_train.shape[1]),
        'cat_features': [common_cols[i] for i in cat_idx]
    }
    (outdir / 'catboost_summary.json').write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
