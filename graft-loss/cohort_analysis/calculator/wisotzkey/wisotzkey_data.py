"""
Build Wisotzkey et al. variable set from the same SAS/calculator data source.

Uses the same phts_txpl_ml.sas7bdat (or parquet cache) as the rest of the calculator
pipeline. Produces cohort-specific datasets (CHD, Myocardio, Combined) with the
Wisotzkey variable set for replication or Wisotzkey-based models.

Mirrors logic in scripts/R/wisotzkey-vars.R and calculator/wisotzkey/wisotzkey-vars.R.
"""

from pathlib import Path
from typing import Dict, Optional, List

import pandas as pd


def _col(df: pd.DataFrame, *candidates: str) -> Optional[str]:
    """Return first column name that exists (case-insensitive)."""
    lower_map = {c.lower(): c for c in df.columns}
    for cand in candidates:
        if cand in df.columns:
            return cand
        if cand.lower() in lower_map:
            return lower_map[cand.lower()]
    return None


def _filter_cohort(df: pd.DataFrame, cohort: str) -> pd.DataFrame:
    """Filter to one cohort by PRIM_DX/prim_dx. Same logic as run_shap_ffa_workflow."""
    prim = _col(df, "PRIM_DX", "prim_dx")
    if prim is None:
        return df
    if cohort == "CHD":
        return df[df[prim] == "Congenital HD"].copy()
    if cohort == "Myocardio":
        return df[df[prim].isin(["Cardiomyopathy", "Myocarditis"])].copy()
    if cohort == "Combined":
        return df[df[prim].isin(["Congenital HD", "Cardiomyopathy", "Myocarditis"])].copy()
    return df


def make_wisotzkey_data(df: pd.DataFrame, cohort: str = "Combined") -> pd.DataFrame:
    """
    Build Wisotzkey-et-al. variable set for one cohort.

    Uses the same cohort definitions as the calculator (CHD = Congenital HD,
    Myocardio = Cardiomyopathy/Myocarditis, Combined = all three). Requires
    raw or calculator-style columns: PRIM_DX/prim_dx, WEIGHT_TXPL, HEIGHT_TXPL,
    TXCREAT_R, TXSA_R, TXBUN_R, TXECMO, TXPL_YEAR, TXALT, CHD_SV, HXSURG, HXMED,
    TXMCSD, outcome (or outcome column from calculator).

    Parameters
    ----------
    df : pd.DataFrame
        Full calculator/SAS-sourced data (before or after prepare_calculator_features).
    cohort : str
        One of "CHD", "Myocardio", "Combined".

    Returns
    -------
    pd.DataFrame
        One row per patient in cohort; columns = outcome + Wisotzkey variables.
    """
    work = _filter_cohort(df, cohort)
    if work.empty:
        return work

    # Column lookups (accept common casing)
    w = _col(work, "WEIGHT_TXPL", "weight_txpl")
    h = _col(work, "HEIGHT_TXPL", "height_txpl")
    cr = _col(work, "TXCREAT_R", "txcreat_r")
    sa = _col(work, "TXSA_R", "txsa_r")
    bun = _col(work, "TXBUN_R", "txbun_r")
    alt = _col(work, "TXALT", "txalt")
    year = _col(work, "TXPL_YEAR", "txpl_year")
    prim = _col(work, "PRIM_DX", "prim_dx")
    out = _col(work, "outcome", "OUTCOME")

    if not all([w, h, cr, sa, bun, year, prim]):
        missing = [x for x in ["WEIGHT_TXPL", "HEIGHT_TXPL", "TXCREAT_R", "TXSA_R", "TXBUN_R", "TXPL_YEAR", "PRIM_DX"] if not _col(work, x, x.lower())]
        raise ValueError(f"Missing columns for Wisotzkey: {missing}. Available: {list(work.columns)}")

    # Derived (Wisotzkey paper)
    work = work.copy()
    work["_bmi_txpl"] = 703 * work[w] / (work[h] ** 2)
    work["_egfr_txpl"] = 0.413 * (work[h] * 2.54) / work[cr].clip(lower=0.001)

    # Binary / numeric Wisotzkey vars
    chd_sv = _col(work, "CHD_SV", "chd_sv")
    hxsurg = _col(work, "HXSURG", "hxsurg")
    hxmed = _col(work, "HXMED", "hxmed")
    txmcsd = _col(work, "TXMCSD", "txmcsd")
    txecmo = _col(work, "TXECMO", "txecmo")

    out_df = pd.DataFrame()
    if out:
        out_df["outcome"] = work[out]
    out_df["CHD"] = (work[prim] == "Congenital HD").astype(int)
    out_df["TXMCSD"] = work[txmcsd].fillna(0) if txmcsd else 0
    out_df["CHD_SV"] = work[chd_sv].fillna(0) if chd_sv else 0
    out_df["HXSURG"] = work[hxsurg].fillna(0) if hxsurg else 0
    out_df["HXMED"] = work[hxmed].fillna(0) if hxmed else 0
    out_df["ALBUMIN_UNDER_3"] = (work[sa] < 3).astype(int)
    out_df["BUN_UNDER_15"] = (work[bun] < 15).astype(int)
    out_df["eGFR_UNDER_60"] = (work["_egfr_txpl"] < 60).astype(int)
    out_df["TXECMO"] = work[txecmo].fillna(0) if txecmo else 0
    out_df["YR_UNDER_2015"] = (work[year] < 2015).astype(int)
    out_df["WEIGHT_UNDER_75"] = (work[w] < 75).astype(int)
    out_df["BMI_UNDER_18"] = (work["_bmi_txpl"] < 18).fillna(0).astype(int)
    if alt:
        out_df["ALT_UNDER_30"] = ((work[alt] < 30) | work[alt].isna()).astype(int)
        out_df["ALT_OVER_50"] = (work[alt] >= 50).astype(int)
    else:
        out_df["ALT_UNDER_30"] = 0
        out_df["ALT_OVER_50"] = 0

    return out_df


def make_wisotzkey_data_by_cohort(
    df: pd.DataFrame,
    out_dir: Optional[Path] = None,
    cohorts: Optional[List[str]] = None,
) -> Dict[str, pd.DataFrame]:
    """
    Build Wisotzkey-vars datasets for CHD, Myocardio, and Combined from the same dataframe.

    Parameters
    ----------
    df : pd.DataFrame
        Full data (same SAS source as calculator pipeline).
    out_dir : Path, optional
        If set, write wisotzkey_CHD.csv, wisotzkey_Myocardio.csv, wisotzkey_Combined.csv.
    cohorts : list of str, optional
        Default ["CHD", "Myocardio", "Combined"].

    Returns
    -------
    dict
        cohort -> DataFrame with outcome + Wisotzkey variables.
    """
    if cohorts is None:
        cohorts = ["CHD", "Myocardio", "Combined"]
    result = {}
    for cohort in cohorts:
        result[cohort] = make_wisotzkey_data(df, cohort=cohort)

    if out_dir is not None:
        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        for cohort in cohorts:
            path = out_dir / f"wisotzkey_{cohort}.csv"
            result[cohort].to_csv(path, index=False)
    return result
