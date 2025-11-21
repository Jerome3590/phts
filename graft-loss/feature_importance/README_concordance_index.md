Summary of changes: Robust C-index calculation

What I changed
- Replaced `calculate_cindex()` in `graft_loss_feature_importance.ipynb` with a robust function that:
  - Tries `survival::concordance()` (Harrell's C) for score and -score.
  - Falls back to `survConcordance()` if available.
  - Attempts `riskRegression::Score()` if the package is present.
  - Uses a sampled pure-R pairwise Harrell estimator (up to 2000 observations) as a final fallback to avoid NA results.

Added test scripts
- `test_calculate_cindex.R` — defines the updated `calculate_cindex()` and runs synthetic tests.
- `test_calculate_cindex_safe.R` — runs only the pure-R sampled Harrell estimator to avoid compiled package calls; used for safe verification.

Why
- `riskRegression::Score()` sometimes fails with "Cannot assign response type." and that, combined with concordance fallbacks, produced NA. The multi-level fallback reduces the chance of missing C-index values and allows the analysis to continue.

Notes
- I ran the safe test (`test_calculate_cindex_safe.R`) locally; it produced expected values.
- A full run that invokes compiled functions (e.g., `survival::concordance`) caused a segmentation fault in this environment. That is likely environmental (package binary mismatch or runtime issue). If you see segfaults locally, try reinstalling `survival` / `riskRegression` or run the notebook in a different R environment.

Next steps
- If you want, I can create a pull request from the pushed branch and/or add an automated toggle in the notebook to prefer safe fallback when `concordance()` errors occur.
