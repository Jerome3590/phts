#!/usr/bin/env Rscript

# Thin wrapper to load the shared survival_helpers.R from the top-level
# project scripts/R directory, while allowing existing notebook code
# that does source(here("scripts", "R", "survival_helpers.R")) to work
# when here() is rooted at graft-loss/cohort_analysis.

if (!requireNamespace("here", quietly = TRUE)) {
  stop("The 'here' package is required to locate top-level scripts.")
}

# here() in cohort_analysis resolves to .../graft-loss/cohort_analysis
root_helpers <- here::here("..", "..", "scripts", "R", "survival_helpers.R")

if (!file.exists(root_helpers)) {
  stop("Cannot find top-level survival_helpers.R at: ", root_helpers)
}

source(root_helpers)


