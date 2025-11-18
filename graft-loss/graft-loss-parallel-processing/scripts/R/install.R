#!/usr/bin/env Rscript

# install.R
# Package installation script for the graft loss pipeline

cat("=== Package Installation for Graft Loss Pipeline ===\n")
cat("Timestamp:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("R Version:", R.version.string, "\n\n")

# Set CRAN mirror
options(repos = c(CRAN = "https://cloud.r-project.org"))

# Set environment variables for package installation
Sys.setenv(R_REMOTES_NO_ERRORS_FROM_WARNINGS = "true")

# Core packages required for the pipeline
core_packages <- c(
  # Data manipulation and analysis
  "dplyr", "tidyr", "purrr", "readr", "here",
  
  # Machine learning and modeling
  "ranger", "aorsf", "survival", "survminer",
  
  # Parallel processing
  "future", "furrr", "parallelly",
  
  # Visualization
  "ggplot2", "plotly", "flextable",
  
  # Utilities
  "conflicted", "withr", "fs", "tibble", "glue"
)

# Optional packages (may not be available on all systems)
optional_packages <- c(
  "qs",           # Fast serialization
  "catboost",     # CatBoost (if available)
  "rpart.plot",   # Tree plotting
  "pROC",         # ROC analysis
  "survcomp"      # Survival analysis comparisons
)

# Function to install packages safely
install_package_safely <- function(pkg) {
  cat(sprintf("Installing %s... ", pkg))
  
  tryCatch({
    if (!requireNamespace(pkg, quietly = TRUE)) {
      install.packages(pkg, dependencies = TRUE, quiet = TRUE)
      cat("✓\n")
    } else {
      cat("already installed\n")
    }
  }, error = function(e) {
    cat(sprintf("✗ Failed: %s\n", conditionMessage(e)))
    return(FALSE)
  })
  
  return(TRUE)
}

# Install core packages
cat("Installing core packages...\n")
core_success <- sapply(core_packages, install_package_safely)

# Install optional packages
cat("\nInstalling optional packages...\n")
optional_success <- sapply(optional_packages, install_package_safely)

# Summary
cat("\n=== Installation Summary ===\n")
cat("Core packages:", sum(core_success), "/", length(core_success), "installed\n")
cat("Optional packages:", sum(optional_success), "/", length(optional_success), "installed\n")

if (all(core_success)) {
  cat("✓ All core packages installed successfully\n")
} else {
  cat("✗ Some core packages failed to install\n")
  failed_core <- names(core_success)[!core_success]
  cat("Failed core packages:", paste(failed_core, collapse = ", "), "\n")
}

cat("\nInstallation complete at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
