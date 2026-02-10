"""
Top features from SHAP/FFA causal importance (final workflow).

Used to train the single model (Combined_top) on only these features.
Limited to features with demonstrated high importance or high causality:
- Top 10 by average importance: sec_dx, donor_age, txalt, lbun_r, txbun_r,
  egfr_change, chd_sv, donor_size_ratio, hxsurg, lsbaosat
- Next five: bmi_txpl, lstp_r, egfr_tx, donor_weight_ratio, txsa_r
Expand only when new SHAP/FFA runs provide a clear ranked list for additional features.
"""

from typing import List

# Top 15: high importance/causality only (from combined + per-model top-10)
TOP_CAUSAL_FEATURES: List[str] = [
    "sec_dx",
    "donor_age",
    "txalt",
    "lbun_r",
    "txbun_r",
    "egfr_change",
    "chd_sv",
    "donor_size_ratio",
    "hxsurg",
    "lsbaosat",
    "bmi_txpl",
    "lstp_r",
    "egfr_tx",
    "donor_weight_ratio",
    "txsa_r",
]


def get_top_causal_features() -> List[str]:
    """Return the list of top causal/importance features for reduced model training."""
    return list(TOP_CAUSAL_FEATURES)
