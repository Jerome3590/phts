#!/usr/bin/env Rscript

##' Package Cache Management
##' 
##' Utility script for managing package installation cache.
##' Run this if you encounter package installation issues.

# Source the smart setup functions
source(file.path(dirname(rstudioapi::getSourceEditorContext()$path %||% getwd()), "smart_setup.R"))

# Clear cache and force fresh package check
clear_package_cache()

# Force recheck of all packages
cat("Force-checking all packages...\n")
setup_packages(force_check = TRUE, quiet = FALSE)

cat("Package cache reset complete.\n")
cat("Next pipeline run will use fresh package status.\n")