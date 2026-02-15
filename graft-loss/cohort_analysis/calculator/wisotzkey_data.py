"""
Wisotzkey et al. variable set — cohort versions (CHD, Myocardio, Combined).

Uses the same SAS dataset as the calculator pipeline (phts_txpl_ml.sas7bdat).
Builds the Wisotzkey risk-factor variables per cohort for replication or
Wisotzkey-based models. Mirrors scripts/R/wisotzkey-vars.R.

Wisotzkey et al. (2023). Risk factors for 1-year allograft loss in pediatric
heart transplant. Pediatric Transplantation.
"""

import logging
from pathlib import Path
from typing import Dict, List, Optional

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# Predictor variables used by Wisotzkey models (excludes outcome, time, status).
# Same set for all cohorts; models are trained per cohort on these features only.
WISOTZKEY_FEATURES: List[str] = [
    "CHD",               # 1 = Congenital HD, 0 = Cardiomyopathy/Myocarditis
    "TXMCSD",            # Mechanical circulatory support device at transplant
    "CHD_SV",            # CHD: Single ventricle
    "HXSURG",            # Prior heart surgeries
    "HXMED",             # Medical history at listing
    "ALBUMIN_UNDER_3",   # Serum albumin at transplant < 3 g/dL
    "BUN_UNDER_15",      # BUN at transplant < 15 mg/dL
    "eGFR_UNDER_60",     # eGFR at transplant < 60 (Schwartz formula)
    "TXECMO",            # ECMO at transplant
    "YR_UNDER_2015",     # Transplant year < 2015
    "WEIGHT_UNDER_75",   # Weight at transplant < 75 kg
    "BMI_UNDER_18",      # BMI at transplant < 18
    "ALT_UNDER_30",      # ALT at transplant < 30 U/L (or missing)
    "ALT_OVER_50",       # ALT at transplant >= 50 U/L
]

# Same paths as run_shap_ffa_workflow for SAS data
CALCULATOR_DIR = Path(__file__).parent
PROJECT_ROOT = CALCULATOR_DIR.parent.parent.parent
SAS_PATHS = [
    CALCULATOR_DIR.parent.parent / "data" / "phts_txpl_ml.sas7bdat",
    PROJECT_ROOT / "graft-loss" / "data" / "phts_txpl_ml.sas7bdat",
]


def _col(df: pd.DataFrame, *candidates: str) -> Optional[pd.Series]:
    """Return first existing column from df (case-insensitive match)."""
    cols = {c.lower(): c for c in df.columns}
    for name in candidates:
        k = name.lower()
        if k in cols:
            return df[cols[k]]
    return None


def _filter_cohort_prim_dx(df: pd.DataFrame, cohort: str) -> pd.DataFrame:
    """Filter to one cohort by primary diagnosis. Same logic as R filter_cohort_prim_dx."""
    prim_dx = _col(df, "PRIM_DX", "prim_dx")
    if prim_dx is None:
        return df
    if cohort == "CHD":
        return df[prim_dx == "Congenital HD"].copy()
    if cohort == "Myocardio":
        return df[prim_dx.isin(["Cardiomyopathy", "Myocarditis"])].copy()
    if cohort == "Combined":
        return df[prim_dx.isin(["Congenital HD", "Cardiomyopathy", "Myocarditis"])].copy()
    return df


def make_wisotzkey_data(df: pd.DataFrame, cohort: str = "Combined") -> pd.DataFrame:
    """
    Build Wisotzkey-et-al. variable set from raw calculator-style data.

    Uses the same variable definitions as scripts/R/wisotzkey-vars.R.
    DataFrame should have SAS-style columns (e.g. PRIM_DX, WEIGHT_TXPL, TXCREAT_R, ...).

    Parameters
    ----------
    df : pd.DataFrame
        Raw data (e.g. from phts_txpl_ml.sas7bdat). Must include outcome and
        PRIM_DX/prim_dx, WEIGHT_TXPL, HEIGHT_TXPL, TXCREAT_R, TXSA_R, TXBUN_R,
        TXECMO, TXPL_YEAR, TXALT, CHD_SV, HXSURG, HXMED, TXMCSD.
    cohort : str
        One of "CHD", "Myocardio", "Combined". Filters to that cohort first.

    Returns
    -------
    pd.DataFrame
        Outcome plus Wisotzkey variables only.
    """
    df = _filter_cohort_prim_dx(df, cohort)
    if df.empty:
        return df

    # Resolve column names (case-insensitive)
    prim_dx = _col(df, "PRIM_DX", "prim_dx")
    weight = _col(df, "WEIGHT_TXPL", "weight_txpl")
    height = _col(df, "HEIGHT_TXPL", "height_txpl")
    txcreat = _col(df, "TXCREAT_R", "txcreat_r")
    txsa = _col(df, "TXSA_R", "txsa_r")
    txbun = _col(df, "TXBUN_R", "txbun_r")
    txecmo = _col(df, "TXECMO", "txecmo")
    txpl_year = _col(df, "TXPL_YEAR", "txpl_year")
    txalt = _col(df, "TXALT", "txalt")
    chd_sv = _col(df, "CHD_SV", "chd_sv")
    hxsurg = _col(df, "HXSURG", "hxsurg")
    hxmed = _col(df, "HXMED", "hxmed")
    txmcsd = _col(df, "TXMCSD", "txmcsd")
    outcome = _col(df, "outcome", "OUTCOME")

    # Derived (Wisotzkey formulas) — same as R
    height_cm = (height * 2.54) if height is not None else pd.Series(np.nan, index=df.index)
    creatinine_safe = txcreat.clip(lower=0.001) if txcreat is not None else pd.Series(1.0, index=df.index)
    bmi_txpl = (703 * weight / (height ** 2)) if (weight is not None and height is not None) else pd.Series(np.nan, index=df.index)
    egfr_txpl = 0.413 * height_cm / creatinine_safe

    out = pd.DataFrame(index=df.index)
    if outcome is not None:
        out["outcome"] = outcome

    out["CHD"] = (1 * (prim_dx == "Congenital HD")) if prim_dx is not None else 0
    out["TXMCSD"] = txmcsd.fillna(0) if txmcsd is not None else 0
    out["CHD_SV"] = chd_sv.fillna(0) if chd_sv is not None else 0
    out["HXSURG"] = hxsurg.fillna(0) if hxsurg is not None else 0
    out["HXMED"] = hxmed.fillna(0) if hxmed is not None else 0

    out["ALBUMIN_UNDER_3"] = (1 * (txsa < 3)) if txsa is not None else 0
    out["BUN_UNDER_15"] = (1 * (txbun < 15)) if txbun is not None else 0
    out["eGFR_UNDER_60"] = 1 * (egfr_txpl < 60)

    out["TXECMO"] = txecmo.fillna(0) if txecmo is not None else 0
    out["YR_UNDER_2015"] = (1 * (txpl_year < 2015)) if txpl_year is not None else 0
    out["WEIGHT_UNDER_75"] = (1 * (weight < 75)) if weight is not None else 0
    out["BMI_UNDER_18"] = np.where(np.isnan(bmi_txpl), 0, (1 * (bmi_txpl < 18)))
    if txalt is not None:
        out["ALT_UNDER_30"] = np.where(txalt.isna(), 1, (1 * (txalt < 30)))
        out["ALT_OVER_50"] = 1 * (txalt >= 50)
    else:
        out["ALT_UNDER_30"] = 1
        out["ALT_OVER_50"] = 0

    return out


def make_wisotzkey_data_for_training(df: pd.DataFrame, cohort: str = "Combined") -> pd.DataFrame:
    """
    Build Wisotzkey-vars DataFrame with survival targets (time, status) and txpl_year.

    Same variables as make_wisotzkey_data plus ev_time, ev_type, time, status, txpl_year
    so the result can be used by train_python_models for survival model training.

    Parameters
    ----------
    df : pd.DataFrame
        Raw SAS data (must include int_dead, int_graft_loss, dtx_patient, graft_loss, TXPL_YEAR).
    cohort : str
        One of "CHD", "Myocardio", "Combined".

    Returns
    -------
    pd.DataFrame
        Columns: WISOTZKEY_FEATURES + time, status, txpl_year (ev_time, ev_type kept for compatibility).
    """
    out = make_wisotzkey_data(df, cohort=cohort)
    if out.empty:
        return out

    # Align with filtered cohort rows (same index as out)
    raw_filtered = _filter_cohort_prim_dx(df, cohort)
    int_dead = _col(raw_filtered, "int_dead", "INT_DEAD")
    int_graft_loss = _col(raw_filtered, "int_graft_loss", "INT_GRAFT_LOSS")
    dtx_patient = _col(raw_filtered, "dtx_patient", "DTX_PATIENT")
    graft_loss = _col(raw_filtered, "graft_loss", "GRAFT_LOSS")
    txpl_year = _col(raw_filtered, "TXPL_YEAR", "txpl_year")

    if int_dead is not None and int_graft_loss is not None:
        ev_time = pd.concat([int_dead, int_graft_loss], axis=1).min(axis=1, skipna=True)
    else:
        ev_time = _col(raw_filtered, "outcome_int_graft_loss", "ev_time")
        if ev_time is None:
            raise ValueError("Cannot derive ev_time: need int_dead and int_graft_loss in SAS data")
    if dtx_patient is not None and graft_loss is not None:
        ev_type = pd.concat([dtx_patient, graft_loss], axis=1).max(axis=1, skipna=True)
    else:
        ev_type = _col(raw_filtered, "outcome_graft_loss", "ev_type")
        if ev_type is None:
            raise ValueError("Cannot derive ev_type: need dtx_patient and graft_loss in SAS data")

    out = out.copy()
    out["ev_time"] = ev_time.reindex(out.index).values
    out["ev_type"] = ev_type.reindex(out.index).values
    out["time"] = out["ev_time"]
    out["status"] = (out["ev_type"] == 1).astype(int)
    if txpl_year is not None:
        out["txpl_year"] = txpl_year.reindex(out.index).values
    # Fix non-positive times (match train_python_models)
    if (out["time"] <= 0).any():
        out.loc[out["time"] <= 0, "time"] = 0.1
        out.loc[out["time"] <= 0, "ev_time"] = 0.1
    return out


def make_wisotzkey_data_by_cohort(
    df: pd.DataFrame,
    out_dir: Optional[Path] = None,
) -> Dict[str, pd.DataFrame]:
    """
    Build Wisotzkey-vars datasets for all cohorts (CHD, Myocardio, Combined).

    Parameters
    ----------
    df : pd.DataFrame
        Raw data (same SAS dataset as calculator pipeline).
    out_dir : Path, optional
        If set, write wisotzkey_CHD.csv, wisotzkey_Myocardio.csv, wisotzkey_Combined.csv.

    Returns
    -------
    dict
        Keys "CHD", "Myocardio", "Combined"; values are DataFrames.
    """
    cohorts = ["CHD", "Myocardio", "Combined"]
    out = {c: make_wisotzkey_data(df, cohort=c) for c in cohorts}

    if out_dir is not None:
        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        for c in cohorts:
            path = out_dir / f"wisotzkey_{c}.csv"
            out[c].to_csv(path, index=False)
            logger.info("Wrote %s", path)

    return out


def load_sas_for_wisotzkey() -> pd.DataFrame:
    """
    Load the same SAS dataset used by the calculator pipeline (raw, no feature prep).

    Returns
    -------
    pd.DataFrame
        Raw SAS data for building Wisotzkey vars.

    Raises
    ------
    FileNotFoundError
        If phts_txpl_ml.sas7bdat not found.
    """
    data_path = None
    for path in SAS_PATHS:
        if path.exists():
            data_path = path
            break
    if data_path is None:
        raise FileNotFoundError(
            f"Cannot find phts_txpl_ml.sas7bdat. Checked: {SAS_PATHS}. "
            "Same file is used by the calculator pipeline."
        )
    logger.info("Loading SAS data from %s (same dataset as calculator pipeline)", data_path)
    try:
        import pyreadstat
        df, _ = pyreadstat.read_sas7bdat(str(data_path))
    except ImportError:
        try:
            import sas7bdat
            with sas7bdat.SAS7BDAT(str(data_path)) as reader:
                df = reader.to_dataframe()
        except ImportError:
            try:
                df = pd.read_sas(str(data_path))
            except Exception as e:
                raise ImportError(
                    "Need pyreadstat, sas7bdat, or pandas with SAS support. "
                    "Install with: pip install pyreadstat"
                ) from e
    # Ensure outcome exists (calculator uses graft_loss / ev_type etc.; Wisotzkey may use binary outcome)
    if "outcome" not in df.columns and "OUTCOME" not in df.columns:
        for name in ["graft_loss", "GRAFT_LOSS", "ev_type", "EV_TYPE"]:
            if name in df.columns:
                df["outcome"] = df[name]
                break
    return df


def load_wisotzkey_data_for_training(cohort: str) -> pd.DataFrame:
    """
    Load the same SAS dataset and return Wisotzkey-vars DataFrame ready for survival training.

    Use this in train_python_models when training Wisotzkey-variant models (--wisotzkey_vars_only).
    Columns: WISOTZKEY_FEATURES + time, status, txpl_year, outcome, ev_time, ev_type.

    Parameters
    ----------
    cohort : str
        One of "CHD", "Myocardio", "Combined".

    Returns
    -------
    pd.DataFrame
        Ready for survival training (filter valid time/status after if needed).
    """
    df = load_sas_for_wisotzkey()
    out = make_wisotzkey_data_for_training(df, cohort=cohort)
    # Drop outcome from predictor set (training uses time/status only)
    if "outcome" in out.columns:
        out = out.drop(columns=["outcome"])
    logger.info("Wisotzkey training data for cohort %s: %d rows, %d features", cohort, len(out), len(WISOTZKEY_FEATURES))
    return out
