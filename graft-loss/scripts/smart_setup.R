#!/usr/bin/env Rscript

##' Smart Package Manager for Graft Loss Pipeline
##' 
##' This script provides intelligent package management:
##' - Checks package availability before attempting installation
##' - Caches installation status to avoid repeated checks
##' - Provides fast loading for interactive sessions
##' - Supports both fresh installs and updates

# Create cache directory if it doesn't exist
cache_dir <- file.path(tempdir(), "graft_loss_cache")
if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
cache_file <- file.path(cache_dir, "package_status.rds")

# Helper functions
check_package_available <- function(pkg) {
  requireNamespace(pkg, quietly = TRUE)
}

get_package_cache <- function() {
  if (file.exists(cache_file)) {
    readRDS(cache_file)
  } else {
    list()
  }
}

save_package_cache <- function(cache) {
  saveRDS(cache, cache_file)
}

# Smart package installer
smart_install <- function(packages, force_check = FALSE, quiet = TRUE) {
  cache <- get_package_cache()
  
  # Check which packages need attention
  missing_pkgs <- c()
  
  for (pkg in packages) {
    # Check cache first (unless forced)
    if (!force_check && !is.null(cache[[pkg]]) && cache[[pkg]]) {
      next  # Package was previously confirmed available
    }
    
    # Verify package availability
    if (!check_package_available(pkg)) {
      missing_pkgs <- c(missing_pkgs, pkg)
      cache[[pkg]] <- FALSE
    } else {
      cache[[pkg]] <- TRUE
    }
  }
  
  # Install missing packages
  if (length(missing_pkgs) > 0) {
    if (!quiet) {
      cat("Installing missing packages:", paste(missing_pkgs, collapse = ", "), "\n")
    }
    
    # Dynamic parallelism for installs
    ncpus <- tryCatch({
      max(1L, min(8L, parallel::detectCores() - 1L))
    }, error = function(e) 2L)
    
    # Install packages
    install.packages(missing_pkgs, Ncpus = ncpus, quiet = quiet)
    
    # Update cache for successfully installed packages
    for (pkg in missing_pkgs) {
      if (check_package_available(pkg)) {
        cache[[pkg]] <- TRUE
      }
    }
  }
  
  # Save updated cache
  save_package_cache(cache)
  
  # Return status
  if (!quiet && length(missing_pkgs) > 0) {
    cat("Package installation complete.\n")
  }
  
  invisible(missing_pkgs)
}

# Fast package loading (assumes packages are installed)
fast_load_packages <- function(packages, quiet = TRUE) {
  for (pkg in packages) {
    if (!quiet) cat("Loading", pkg, "\n")
    suppressPackageStartupMessages(
      library(pkg, character.only = TRUE, quietly = quiet)
    )
  }
}

# Main package lists
core_packages <- c(
  "conflicted", "dotenv", "drake", "R.utils", "haven", "janitor", 
  "magrittr", "here", "foreach", "tidyverse", "tidyposterior", 
  "ranger", "survival", "rms", "obliqueRSF", "xgboost", 
  "riskRegression", "naniar", "MASS", "Hmisc", "rstanarm"
)

parallel_packages <- c(
  "future", "furrr", "future.apply"
)

reporting_packages <- c(
  "table.glue", "gtsummary", "officer", "glue", "flextable", 
  "devEMF", "diagram", "paletteer", "ggdist", "ggsci", 
  "cmprsk", "patchwork"
)

pipeline_packages <- c(
  "aorsf", "recipes", "rsample", "tidymodels", "embed", "magick"
)

all_packages <- c(core_packages, parallel_packages, reporting_packages, pipeline_packages)

# Main functions for external use
setup_packages <- function(force_check = FALSE, quiet = TRUE) {
  # Ensure remotes is available for GitHub packages
  if (!check_package_available("remotes")) {
    install.packages("remotes", quiet = quiet)
  }
  
  # Install missing CRAN packages
  smart_install(all_packages, force_check = force_check, quiet = quiet)
  
  # Handle special GitHub package
  if (!check_package_available("xgboost.surv")) {
    if (!quiet) cat("Installing xgboost.surv from GitHub...\n")
    try({
      remotes::install_github("bcjaeger/xgboost.surv", 
                             upgrade = "never", quiet = quiet)
    }, silent = quiet)
  }
  
  invisible(TRUE)
}

load_pipeline_packages <- function(minimal = FALSE, quiet = TRUE) {
  if (minimal) {
    # Load only essential packages for quick setup (data + parallel)
    essential <- c("conflicted", "here", "dotenv", "tidyverse", "future", "furrr")
    fast_load_packages(essential, quiet = quiet)
  } else {
    # Load all packages
    fast_load_packages(all_packages, quiet = quiet)
    
    # Load GitHub package if available
    if (check_package_available("xgboost.surv")) {
      suppressPackageStartupMessages(library(xgboost.surv, quietly = quiet))
    }
  }
  
  # Set up conflict preferences
  if (check_package_available("conflicted")) {
    conflicted::conflict_prefer("roc", "pROC")
    conflicted::conflict_prefer("filter", "dplyr")
    conflicted::conflict_prefer("slice", "dplyr")
    conflicted::conflict_prefer("select", "dplyr")
  }
  
  invisible(TRUE)
}

# Clear package cache (for troubleshooting)
clear_package_cache <- function() {
  if (file.exists(cache_file)) {
    unlink(cache_file)
    cat("Package cache cleared.\n")
  }
  invisible(TRUE)
}

# Export main functions
if (!interactive()) {
  # Command line usage: Rscript smart_setup.R
  setup_packages(quiet = FALSE)
}