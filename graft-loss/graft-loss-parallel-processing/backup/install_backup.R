#!/usr/bin/env Rscript

# CRAN mirror
options(repos = "https://cloud.r-project.org")

# Helper: dynamic parallelism for installs
ncpus <- tryCatch({
  max(1L, min(8L, parallel::detectCores() - 1L))
}, error = function(e) 2L)

# Ensure remotes is available (for GitHub installs)
if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes", Ncpus = ncpus, quiet = TRUE)
}

# Core packages used across scripts and notebooks
pkgs <- c(
  "conflicted", "dotenv", "drake", "R.utils", "haven", "janitor", "magrittr", "here",
  "foreach", "tidyverse", "tidyposterior", "ranger",
  "survival", "rms", "obliqueRSF", "xgboost", "riskRegression",
  "naniar", "MASS", "Hmisc", "rstanarm", "table.glue", "gtsummary", "officer",
  "glue", "flextable", "devEMF", "diagram", "paletteer", "ggdist",
  "ggsci", "cmprsk", "patchwork",
  # Added for pipeline/notebook parallelism & recipes
  "aorsf", "furrr", "future", "recipes", "rsample"
)

# Find and install missing CRAN packages
inst <- setdiff(pkgs, rownames(installed.packages()))
if (length(inst)) {
  install.packages(inst, Ncpus = ncpus, quiet = TRUE)
}

# Re-check a few heavier deps individually (sometimes skipped due to transient issues)
for (p in c("obliqueRSF", "rstanarm")) {
  if (!requireNamespace(p, quietly = TRUE)) {
    try(install.packages(p, Ncpus = ncpus, quiet = TRUE), silent = TRUE)
  }
}

# Install GitHub survival booster if missing
if (!requireNamespace("xgboost.surv", quietly = TRUE)) {
  try(remotes::install_github("bcjaeger/xgboost.surv", upgrade = "never", quiet = TRUE), silent = TRUE)
}

# Install meta toolkits only if not present
if (!requireNamespace("tidymodels", quietly = TRUE)) install.packages("tidymodels", Ncpus = ncpus)
if (!requireNamespace("embed", quietly = TRUE)) install.packages("embed", Ncpus = ncpus)
if (!requireNamespace("magick", quietly = TRUE)) install.packages("magick", Ncpus = ncpus)

message("Package installation complete. If any package failed due to system libraries, install OS deps and rerun this script.")
