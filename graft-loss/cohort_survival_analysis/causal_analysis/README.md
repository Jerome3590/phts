# Causal Analysis: LMTP vs Formal Feature Attribution (FFA)

This module complements predictive survival modeling by adding causal estimands (LMTP) and model auditing/explanation (FFA). They answer different questions:

## What each method estimates

- LMTP (Longitudinal Modified Treatment Policies): Population-level causal effects of explicit treatment policies on outcomes (e.g., 1-year survival) with valid uncertainty quantification under standard causal assumptions.
- FFA (Formal Feature Attribution over CatBoost rules): Model-level explanations and rule patterns that describe how a trained model makes predictions. Good for hypothesis generation and auditing, not for causal effects in the target population.

## When to use each

- Use LMTP when you want to evaluate counterfactual policies with time-varying treatments and confounders, and report policy contrasts and survival curves with CIs.
- Use FFA when you want to understand, debug, or communicate what the model learned: feature/rule importance, interactions, and sensitivity of predictions to feature changes.

## Key assumptions and data needs

- LMTP:
  - Data: longitudinal nodes per time k: L_k (covariates), A_k (treatment/decision), C_k (censoring), plus outcome Y/time.
  - Assumptions: consistency, positivity, sequential exchangeability (no unmeasured confounding), correct specification of nuisance functions up to TMLE/SDR with cross-fitting.
  - Outputs: policy-specific risks/survival and contrasts (RD/RR), valid CIs.

- FFA:
  - Data: trained CatBoost model and feature matrix; optionally exported tree rules.
  - Assumptions: explanations are conditional on the fitted model; AXP/minimal hitting sets reflect model logic, not causal structure of the data-generating process.
  - Outputs: AXPs, rule metrics (support, coverage, essentiality, stability), permutation p-values, model flip-tests.

## Limitations

- LMTP: requires careful node construction and policy definition; sensitive to positivity violations; more engineering to build time-varying datasets from follow-up tables.
- FFA: not a causal effect estimator; “causal” flips are counterfactual relative to the model only; susceptible to model bias/leakage.

## Recommended workflow

1) Use FFA to identify candidate decision variables, thresholds, and interactions worth considering as clinical policies.
2) Encode concrete policies and evaluate them with LMTP to obtain population causal contrasts on survival (with CIs).
3) Iterate: if LMTP estimates are unstable (positivity), refine cohorts or policies; if FFA flags suspicious rules, adjust preprocessing or model.

## Files in this module

- `causal_analysis.qmd`: Quarto analysis that runs both LMTP and FFA starters on PHTS data.
- `README.md`: This document.
