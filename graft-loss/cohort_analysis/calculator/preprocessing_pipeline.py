#!/usr/bin/env python3
"""
Complete Preprocessing Pipeline for PHTS Model Training

This module contains ALL feature engineering and preprocessing logic used in model training.
It consolidates preprocessing from multiple locations into a single, reusable pipeline.

Key Preprocessing Steps:
1. Calculated Variables (eGFR, BMI)
2. Dichotomous Variables (high/low thresholds)
3. Combined/Composite Variables (VAD, ECMO, Ventilation, CHD Laterality)
4. Ratio Variables (Donor/Recipient Weight & Size)
5. One-Hot Encoding (Secondary Diagnosis)
6. Change Variables (eGFR change)

Usage:
    from preprocessing_pipeline import prepare_features_for_training
    
    # Load raw data
    df = pd.read_sas('phts_txpl_ml.sas7bdat')
    
    # Apply preprocessing
    df_processed = prepare_features_for_training(df)
    
    # Filter to specific cohort (optional)
    df_chd = filter_by_cohort(df_processed, cohort="CHD")

Author: Consolidated from run_shap_ffa_workflow.py, phts_lambda_function.py
Date: February 17, 2026
"""

import numpy as np
import pandas as pd
import logging
from typing import Optional, List

logger = logging.getLogger(__name__)

# =============================================================================
# CONSTANTS
# =============================================================================

# Secondary Diagnosis levels for one-hot encoding
SEC_DX_LEVELS = [
    "ARVD/C", "Dilated", "Hypertrophic", "MIXED", "Other", "Restrictive", "Unknown"
]

# Donor ischemic time threshold (minutes)
DONISCH_THRESHOLD_MINUTES = 240

# Thresholds for dichotomous variables
BILIRUBIN_HIGH_THRESHOLD = 1.5      # mg/dL
BUN_HIGH_THRESHOLD = 30             # mg/dL
ALBUMIN_LOW_THRESHOLD = 3           # g/dL
ALT_HIGH_THRESHOLD = 90             # U/L

# eGFR category boundaries
EGFR_CATEGORIES = {
    'severe': (0, 30),
    'moderate': (30, 60),
    'mild': (60, 90),
    'normal': (90, float('inf'))
}


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def _sec_dx_safe_col(label: str) -> str:
    """
    Generate safe column name for one-hot encoded secondary diagnosis.
    
    Args:
        label: Original sec_dx level (e.g., "ARVD/C", "Dilated")
    
    Returns:
        Safe column name (e.g., "sec_dx_ARVD_C", "sec_dx_Dilated")
    """
    safe = label.replace("/", "_").replace(" ", "_").strip()
    return f"sec_dx_{safe}"


def _calculate_egfr(height_cm: pd.Series, creatinine: pd.Series) -> pd.Series:
    """
    Calculate eGFR using Schwartz formula for pediatric patients.
    
    Formula: eGFR = 0.413 × height (cm) / creatinine (mg/dL)
    
    Args:
        height_cm: Height in centimeters (convert from PHTS inches with * 2.54 at call site)
        creatinine: Serum creatinine in mg/dL
    
    Returns:
        Series with calculated eGFR values (mL/min/1.73m²)
    """
    egfr = pd.Series(np.nan, index=height_cm.index)
    mask = height_cm.notna() & creatinine.notna() & (creatinine > 0)
    egfr[mask] = 0.413 * height_cm[mask] / creatinine[mask]
    return egfr


def _calculate_bmi(weight_lb: pd.Series, height_in: pd.Series) -> pd.Series:
    """
    Calculate Body Mass Index (BMI) from US customary units (PHTS standard).
    
    Formula: BMI = 703 × weight (lb) / height (in)²
    
    Args:
        weight_lb: Weight in pounds (PHTS WEIGHT_TXPL)
        height_in: Height in inches (PHTS HEIGHT_TXPL)
    
    Returns:
        Series with calculated BMI values (kg/m²)
    """
    bmi = pd.Series(np.nan, index=weight_lb.index)
    mask = weight_lb.notna() & height_in.notna() & (height_in > 0)
    bmi[mask] = (weight_lb[mask] / (height_in[mask] ** 2)) * 703
    return bmi


def _categorize_egfr(egfr: pd.Series) -> pd.Series:
    """
    Categorize eGFR into clinical categories.
    
    Categories:
        - severe: < 30 (Stage 4-5 CKD)
        - moderate: 30-60 (Stage 3 CKD)
        - mild: 60-90 (Stage 2 CKD)
        - normal: >= 90 (Normal/Stage 1)
    
    Args:
        egfr: Series with eGFR values
    
    Returns:
        Series with categorical eGFR classifications
    """
    categories = pd.cut(
        egfr,
        bins=[-np.inf, 30, 60, 90, np.inf],
        labels=["severe", "moderate", "mild", "normal"],
        right=False
    )
    # Convert to string and preserve NaN
    return categories.astype(str).replace("nan", np.nan)


# =============================================================================
# MAIN PREPROCESSING FUNCTION
# =============================================================================

def prepare_features_for_training(df: pd.DataFrame, verbose: bool = True) -> pd.DataFrame:
    """
    Complete preprocessing pipeline for PHTS model training.
    
    This function applies ALL feature engineering steps used in model training:
    1. Converts column names to lowercase for consistency
    2. Calculates derived features (eGFR, BMI)
    3. Creates eGFR categories
    4. Creates dichotomous variables
    5. Creates combined/composite variables
    6. Calculates ratio variables
    7. One-hot encodes secondary diagnosis
    8. Calculates change variables
    
    Args:
        df: Raw dataframe with PHTS data
        verbose: If True, log preprocessing steps
    
    Returns:
        DataFrame with all engineered features
    
    Example:
        >>> df_raw = pd.read_sas('phts_txpl_ml.sas7bdat')
        >>> df_processed = prepare_features_for_training(df_raw)
        >>> print(f"Added {len(df_processed.columns) - len(df_raw.columns)} features")
    """
    if verbose:
        logger.setLevel(logging.INFO)
    
    df = df.copy()
    
    # =========================================================================
    # STEP 1: Standardize column names
    # =========================================================================
    df.columns = [col.lower() for col in df.columns]
    if verbose:
        logger.info(f"Standardized {len(df.columns)} column names to lowercase")
    
    # =========================================================================
    # STEP 2: Calculate derived features - eGFR
    # =========================================================================
    
    # eGFR at transplant (PHTS height_txpl is in inches; Schwartz requires cm)
    if "height_txpl" in df.columns and "txcreat_r" in df.columns:
        if "egfr_tx" not in df.columns:
            height_cm = df["height_txpl"] * 2.54
            df["egfr_tx"] = _calculate_egfr(height_cm, df["txcreat_r"])
            if verbose:
                n_calculated = df["egfr_tx"].notna().sum()
                logger.info(f"Calculated egfr_tx for {n_calculated} patients using Schwartz formula")
    
    # eGFR at listing (PHTS height_listing in inches -> cm for Schwartz)
    if "height_listing" in df.columns and "lcreat_r" in df.columns:
        if "egfr_listing" not in df.columns:
            height_cm = df["height_listing"] * 2.54
            df["egfr_listing"] = _calculate_egfr(height_cm, df["lcreat_r"])
            if verbose:
                n_calculated = df["egfr_listing"].notna().sum()
                logger.info(f"Calculated egfr_listing for {n_calculated} patients")
    
    # =========================================================================
    # STEP 3: Calculate BMI
    # =========================================================================
    
    # BMI: PHTS weight_txpl (lb), height_txpl (in); formula 703 * lb / in²
    if "weight_txpl" in df.columns and "height_txpl" in df.columns:
        if "bmi_txpl" not in df.columns:
            df["bmi_txpl"] = _calculate_bmi(df["weight_txpl"], df["height_txpl"])
            if verbose:
                n_calculated = df["bmi_txpl"].notna().sum()
                logger.info(f"Calculated bmi_txpl for {n_calculated} patients")
    
    # =========================================================================
    # STEP 4: Calculate age in months (if needed)
    # =========================================================================
    
    if "age_txpl_months" not in df.columns and "age_txpl" in df.columns:
        df["age_txpl_months"] = df["age_txpl"] * 12
        if verbose:
            logger.info("Calculated age_txpl_months from age_txpl")
    
    # =========================================================================
    # STEP 5: Create eGFR categories
    # =========================================================================
    
    if "egfr_tx" in df.columns:
        df["egfr_tx_cat"] = _categorize_egfr(df["egfr_tx"])
        if verbose:
            logger.info("Created egfr_tx_cat categories (severe/moderate/mild/normal)")
    
    if "egfr_listing" in df.columns:
        df["egfr_listing_cat"] = _categorize_egfr(df["egfr_listing"])
        if verbose:
            logger.info("Created egfr_listing_cat categories")
    
    # =========================================================================
    # STEP 6: Create dichotomous variables (high/low thresholds)
    # =========================================================================
    
    # Bilirubin > 1.5 mg/dL
    if "txbili_t_r" in df.columns:
        df["txbili_t_r_high"] = (df["txbili_t_r"] > BILIRUBIN_HIGH_THRESHOLD).astype(int)
        if verbose:
            n_high = df["txbili_t_r_high"].sum()
            logger.info(f"Created txbili_t_r_high (>{BILIRUBIN_HIGH_THRESHOLD}): {n_high} patients")
    
    # BUN > 30 mg/dL
    bun_var = None
    for var in ["txbun_r", "TXBUN_R"]:
        if var in df.columns:
            bun_var = var
            break
    if bun_var:
        df["txbun_r_high"] = (df[bun_var] > BUN_HIGH_THRESHOLD).astype(int)
        if verbose:
            n_high = df["txbun_r_high"].sum()
            logger.info(f"Created txbun_r_high from {bun_var} (>{BUN_HIGH_THRESHOLD}): {n_high} patients")
    
    # Albumin < 3 g/dL
    if "txsa_r" in df.columns:
        df["txsa_r_low"] = (df["txsa_r"] < ALBUMIN_LOW_THRESHOLD).astype(int)
        if verbose:
            n_low = df["txsa_r_low"].sum()
            logger.info(f"Created txsa_r_low (<{ALBUMIN_LOW_THRESHOLD}): {n_low} patients")
    
    # ALT > 90 U/L
    alt_var = None
    for var in ["txalt", "TXALT"]:
        if var in df.columns:
            alt_var = var
            break
    if alt_var:
        df["txalt_high"] = (df[alt_var] > ALT_HIGH_THRESHOLD).astype(int)
        if verbose:
            n_high = df["txalt_high"].sum()
            logger.info(f"Created txalt_high from {alt_var} (>{ALT_HIGH_THRESHOLD}): {n_high} patients")
    
    # DONISCH > 240 minutes (4 hours)
    # Convert minutes to binary: >240 = 1, ≤240 = 0, missing = 0
    if "donisch" in df.columns:
        raw = df["donisch"]
        # Only convert if values look like minutes (>1)
        if (raw.dropna() > 1).any():
            df["donisch"] = (raw > DONISCH_THRESHOLD_MINUTES).astype(int)
            df.loc[raw.isna(), "donisch"] = 0  # Missing -> assume ≤240 min
            if verbose:
                n_high = df["donisch"].sum()
                logger.info(f"Created dichotomous donisch (>{DONISCH_THRESHOLD_MINUTES} min): {n_high} patients")
    
    # =========================================================================
    # STEP 7: Create combined/composite variables
    # =========================================================================
    
    # ECMO combined: patient on ECMO at transplant OR at listing
    if "txecmo" in df.columns and "slecmo" in df.columns:
        df["ecmo_combined"] = ((df["txecmo"] == 1) | (df["slecmo"] == 1)).astype(int)
        if verbose:
            n_combined = df["ecmo_combined"].sum()
            logger.info(f"Created ecmo_combined (txecmo OR slecmo): {n_combined} patients")
    
    # VAD combined: ventricular assist device at transplant OR at listing
    if "txvad" in df.columns and "slvad" in df.columns:
        df["vad_combined"] = ((df["txvad"] == 1) | (df["slvad"] == 1)).astype(int)
        if verbose:
            n_combined = df["vad_combined"].sum()
            logger.info(f"Created vad_combined (txvad OR slvad): {n_combined} patients")
    elif "txvad" in df.columns:
        df["vad_combined"] = (df["txvad"] == 1).astype(int)
        if verbose:
            logger.info("Created vad_combined from txvad only")
    elif "slvad" in df.columns:
        df["vad_combined"] = (df["slvad"] == 1).astype(int)
        if verbose:
            logger.info("Created vad_combined from slvad only")
    
    # Ventilation combined: any ventilatory support
    vent_vars = ["txvent", "slvent", "ltxtrach", "hxtrach"]
    available_vent_vars = [v for v in vent_vars if v in df.columns]
    if available_vent_vars:
        df["vent_combined"] = df[available_vent_vars].any(axis=1).astype(int)
        if verbose:
            n_combined = df["vent_combined"].sum()
            logger.info(f"Created vent_combined from {available_vent_vars}: {n_combined} patients")
    
    # CHD Laterality Disorder (composite of 8 CHD laterality variables)
    chd_lat_vars = ["chd_dex", "chd_si", "chd_heter", "chd_iivc", 
                    "chd_bivc", "chd_lsvc", "chd_raa", "chd_avd"]
    available_chd_lat_vars = [v for v in chd_lat_vars if v in df.columns]
    if available_chd_lat_vars:
        df["chd_lat"] = df[available_chd_lat_vars].any(axis=1).astype(int)
        if verbose:
            n_chd_lat = df["chd_lat"].sum()
            logger.info(f"Created chd_lat from {len(available_chd_lat_vars)} variables: {n_chd_lat} patients")
    
    # History of Fontan Associated Liver Disease (binary)
    if "hxfonlvr" in df.columns:
        df["hxfonlvr_bin"] = (df["hxfonlvr"] == 1).astype(int)
        if verbose:
            logger.info("Created hxfonlvr_bin")
    
    # History of dialysis (binary)
    if "hxdysdia" in df.columns:
        df["hxdysdia_bin"] = (df["hxdysdia"] == 1).astype(int)
        if verbose:
            logger.info("Created hxdysdia_bin")
    
    # =========================================================================
    # STEP 8: Calculate ratio variables
    # =========================================================================
    
    # Donor/Recipient Weight Ratio (percentage)
    if "weight_donor" in df.columns and "weight_txpl" in df.columns:
        df["donor_weight_ratio"] = pd.Series(np.nan, index=df.index)
        mask = df["weight_txpl"].notna() & (df["weight_txpl"] > 0)
        df.loc[mask, "donor_weight_ratio"] = (
            (df.loc[mask, "weight_donor"] / df.loc[mask, "weight_txpl"]) * 100
        )
        if verbose:
            n_calculated = df["donor_weight_ratio"].notna().sum()
            logger.info(f"Created donor_weight_ratio for {n_calculated} patients")
    
    # Donor/Recipient Size (Height) Ratio (percentage)
    if "height_donor" in df.columns and "height_txpl" in df.columns:
        df["donor_size_ratio"] = pd.Series(np.nan, index=df.index)
        mask = df["height_txpl"].notna() & (df["height_txpl"] > 0)
        df.loc[mask, "donor_size_ratio"] = (
            (df.loc[mask, "height_donor"] / df.loc[mask, "height_txpl"]) * 100
        )
        if verbose:
            n_calculated = df["donor_size_ratio"].notna().sum()
            logger.info(f"Created donor_size_ratio for {n_calculated} patients")
    
    # =========================================================================
    # STEP 9: Calculate change variables
    # =========================================================================
    
    # Change in eGFR from listing to transplant
    if "egfr_tx" in df.columns and "egfr_listing" in df.columns:
        df["egfr_change"] = df["egfr_tx"] - df["egfr_listing"]
        if verbose:
            n_calculated = df["egfr_change"].notna().sum()
            mean_change = df["egfr_change"].mean()
            logger.info(f"Calculated egfr_change for {n_calculated} patients (mean: {mean_change:.2f})")
    
    # =========================================================================
    # STEP 10: One-hot encode secondary diagnosis
    # =========================================================================
    
    if "sec_dx" in df.columns:
        raw = df["sec_dx"].astype(str).str.strip()
        
        # Create one-hot encoded columns
        for level in SEC_DX_LEVELS:
            col_name = _sec_dx_safe_col(level)
            # Case-insensitive match
            df[col_name] = (raw.str.lower() == level.lower()).astype(int)
        
        # Drop original categorical column
        df = df.drop(columns=["sec_dx"])
        
        if verbose:
            one_hot_cols = [_sec_dx_safe_col(lev) for lev in SEC_DX_LEVELS]
            logger.info(f"One-hot encoded sec_dx into {len(SEC_DX_LEVELS)} columns: {one_hot_cols}")
    
    if verbose:
        logger.info(f"Preprocessing complete. Final shape: {df.shape}")
    
    return df


# =============================================================================
# COHORT FILTERING
# =============================================================================

def filter_by_cohort(df: pd.DataFrame, cohort: str) -> pd.DataFrame:
    """
    Filter dataset by primary diagnosis cohort.
    
    Args:
        df: DataFrame with preprocessed features
        cohort: One of "CHD", "Myocardio", or "Combined"
    
    Returns:
        Filtered DataFrame
    
    Raises:
        ValueError: If cohort is invalid or PRIM_DX column not found
    """
    if cohort not in ["CHD", "Myocardio", "Combined"]:
        raise ValueError(f"Invalid cohort: {cohort}. Must be 'CHD', 'Myocardio', or 'Combined'")
    
    if cohort == "Combined":
        return df.copy()
    
    # Find PRIM_DX column (case-insensitive)
    prim_dx_col = None
    for col in df.columns:
        if col.upper() == "PRIM_DX":
            prim_dx_col = col
            break
    
    if prim_dx_col is None:
        raise ValueError("PRIM_DX column not found in dataframe. Cannot filter by cohort.")
    
    # Normalize values (handle bytes from SAS files)
    prim_dx_values = df[prim_dx_col].astype(str).str.strip()
    prim_dx_values = prim_dx_values.str.replace("^b['\"]|['\"]$", "", regex=True)
    
    if cohort == "CHD":
        mask = prim_dx_values.str.upper() == "CONGENITAL HD"
        logger.info(f"Filtered to CHD cohort: {mask.sum()} / {len(df)} patients")
    elif cohort == "Myocardio":
        mask = prim_dx_values.str.upper().isin(["CARDIOMYOPATHY", "MYOCARDITIS"])
        logger.info(f"Filtered to Myocardio cohort: {mask.sum()} / {len(df)} patients")
    
    return df[mask].copy()


# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

def get_derived_feature_names() -> List[str]:
    """
    Get list of all derived feature names created by preprocessing.
    
    Returns:
        List of feature names created during preprocessing
    """
    derived_features = [
        # Calculated features
        "egfr_tx",
        "egfr_listing",
        "bmi_txpl",
        "age_txpl_months",
        
        # eGFR categories
        "egfr_tx_cat",
        "egfr_listing_cat",
        
        # Dichotomous variables
        "txbili_t_r_high",
        "txbun_r_high",
        "txsa_r_low",
        "txalt_high",
        "donisch",  # converted to binary
        
        # Combined variables
        "ecmo_combined",
        "vad_combined",
        "vent_combined",
        "chd_lat",
        "hxfonlvr_bin",
        "hxdysdia_bin",
        
        # Ratio variables
        "donor_weight_ratio",
        "donor_size_ratio",
        
        # Change variables
        "egfr_change",
    ]
    
    # Add one-hot encoded sec_dx columns
    sec_dx_cols = [_sec_dx_safe_col(level) for level in SEC_DX_LEVELS]
    derived_features.extend(sec_dx_cols)
    
    return derived_features


def load_and_preprocess(
    sas_file_path: str,
    cohort: Optional[str] = None,
    verbose: bool = True
) -> pd.DataFrame:
    """
    Convenience function to load SAS file and apply preprocessing.
    
    Args:
        sas_file_path: Path to phts_txpl_ml.sas7bdat file
        cohort: Optional cohort filter ("CHD", "Myocardio", or "Combined")
        verbose: If True, log preprocessing steps
    
    Returns:
        Preprocessed DataFrame
    
    Example:
        >>> df = load_and_preprocess('data/phts_txpl_ml.sas7bdat', cohort='CHD')
        >>> print(df.shape)
    """
    # Load SAS file
    try:
        import pyreadstat
        df, _ = pyreadstat.read_sas7bdat(sas_file_path)
        if verbose:
            logger.info(f"Loaded {len(df)} rows from {sas_file_path} using pyreadstat")
    except ImportError:
        try:
            df = pd.read_sas(sas_file_path)
            if verbose:
                logger.info(f"Loaded {len(df)} rows from {sas_file_path} using pandas")
        except Exception as e:
            raise ImportError(
                f"Could not load SAS file: {e}. "
                "Install pyreadstat with: pip install pyreadstat"
            )
    
    # Apply preprocessing
    df = prepare_features_for_training(df, verbose=verbose)
    
    # Filter by cohort if specified
    if cohort:
        df = filter_by_cohort(df, cohort)
    
    return df


# =============================================================================
# MAIN (for testing)
# =============================================================================

if __name__ == "__main__":
    """
    Example usage and testing of preprocessing pipeline.
    """
    import sys
    
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    print("="*80)
    print("PHTS Preprocessing Pipeline")
    print("="*80)
    
    # Example 1: Get list of derived features
    print("\n1. Derived Features:")
    print("-" * 80)
    derived = get_derived_feature_names()
    print(f"Total derived features: {len(derived)}")
    print("\nFeature categories:")
    print("  - Calculated: egfr_tx, egfr_listing, bmi_txpl, age_txpl_months")
    print("  - eGFR categories: egfr_tx_cat, egfr_listing_cat")
    print("  - Dichotomous: txbili_t_r_high, txbun_r_high, txsa_r_low, etc.")
    print("  - Combined: ecmo_combined, vad_combined, vent_combined, chd_lat")
    print("  - Ratios: donor_weight_ratio, donor_size_ratio")
    print("  - Change: egfr_change")
    print(f"  - sec_dx one-hot: {len([f for f in derived if 'sec_dx_' in f])} columns")
    
    # Example 2: Show preprocessing constants
    print("\n2. Preprocessing Constants:")
    print("-" * 80)
    print(f"DONISCH_THRESHOLD_MINUTES: {DONISCH_THRESHOLD_MINUTES}")
    print(f"BILIRUBIN_HIGH_THRESHOLD: {BILIRUBIN_HIGH_THRESHOLD} mg/dL")
    print(f"BUN_HIGH_THRESHOLD: {BUN_HIGH_THRESHOLD} mg/dL")
    print(f"ALBUMIN_LOW_THRESHOLD: {ALBUMIN_LOW_THRESHOLD} g/dL")
    print(f"ALT_HIGH_THRESHOLD: {ALT_HIGH_THRESHOLD} U/L")
    print(f"SEC_DX_LEVELS: {SEC_DX_LEVELS}")
    
    # Example 3: Test with actual data (if available)
    print("\n3. Testing with Data:")
    print("-" * 80)
    
    import os
    from pathlib import Path
    
    # Try to find data file
    possible_paths = [
        Path(__file__).parent.parent.parent / "data" / "phts_txpl_ml.sas7bdat",
        Path("c:/Projects/phts/graft-loss/data/phts_txpl_ml.sas7bdat"),
    ]
    
    data_file = None
    for path in possible_paths:
        if path.exists():
            data_file = str(path)
            break
    
    if data_file:
        print(f"Found data file: {data_file}")
        print("\nLoading and preprocessing...")
        
        try:
            # Load and preprocess
            df = load_and_preprocess(data_file, verbose=True)
            
            print(f"\nFinal preprocessed data shape: {df.shape}")
            print(f"Total columns: {len(df.columns)}")
            
            # Check derived features
            derived_present = [f for f in get_derived_feature_names() if f in df.columns]
            print(f"\nDerived features present: {len(derived_present)} / {len(get_derived_feature_names())}")
            
            # Test cohort filtering
            print("\nTesting cohort filtering...")
            df_chd = filter_by_cohort(df, "CHD")
            df_myocardio = filter_by_cohort(df, "Myocardio")
            
            print(f"  CHD cohort: {len(df_chd)} patients")
            print(f"  Myocardio cohort: {len(df_myocardio)} patients")
            print(f"  Total: {len(df)} patients")
            
        except Exception as e:
            print(f"Error during testing: {e}")
            import traceback
            traceback.print_exc()
    else:
        print("Data file not found. Skipping data testing.")
        print("To test with data, place phts_txpl_ml.sas7bdat in the data directory.")
    
    print("\n" + "="*80)
    print("Pipeline documentation complete!")
    print("="*80)
    print("\nUsage:")
    print("  from preprocessing_pipeline import prepare_features_for_training")
    print("  df_processed = prepare_features_for_training(df_raw)")
