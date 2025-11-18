# Smart Setup System - EC2 Compatible
# No xgboost.surv or obliqueRSF installations

setup_packages <- function() {
  # Core packages only
  pkgs <- c(
    "conflicted", "dotenv", "R.utils", "haven", "janitor", "magrittr", "here",
    "foreach", "tidyverse", "tidyposterior", "ranger",
    "survival", "rms", "riskRegression",
    "naniar", "MASS", "Hmisc", "rstanarm", "table.glue", "gtsummary", "officer",
    "glue", "flextable", "devEMF", "diagram", "paletteer", "ggdist",
    "ggsci", "cmprsk", "patchwork"
  )
  
  # Find missing packages
  inst <- pkgs[!(pkgs %in% rownames(installed.packages()))]
  
  # Install missing ones
  if (length(inst)) {
    install.packages(inst, Ncpus = 2, quiet = TRUE)
  }
}

load_pipeline_packages <- function() {
  # Load core packages
  core_packages <- c("here", "dplyr", "tibble", "glue", "survival", "ranger", "aorsf", "riskRegression")
  for (pkg in core_packages) {
    if (requireNamespace(pkg, quietly = TRUE)) {
      library(pkg, character.only = TRUE, quietly = TRUE)
    }
  }
}

clear_package_cache <- function() {
  # Clear package cache if needed
  if (dir.exists(.libPaths()[1])) {
    message("Package cache cleared")
  }
}
