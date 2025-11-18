##' Central configuration management for graft loss pipeline
##' 
##' This module handles:
##' - Package loading with conflict resolution
##' - Environment variable defaults
##' - Global options and settings
##' - Path configurations

# Smart package management
source(here::here("scripts", "smart_setup.R"))

# Core package loading - now uses smart setup
load_core_packages <- function(minimal = FALSE, force_check = FALSE, quiet = TRUE) {
  # Ensure packages are installed (smart check)
  setup_packages(force_check = force_check, quiet = quiet)
  
  # Load packages efficiently
  load_pipeline_packages(minimal = minimal, quiet = quiet)
  
  if (!quiet) cat("✓ Core packages loaded successfully\n")
}

# Conflict resolution (centralized)
setup_conflict_preferences <- function() {
  conflicted::conflict_prefer("roc",       "pROC")
  conflicted::conflict_prefer("filter",    "dplyr")
  conflicted::conflict_prefer("slice",     "dplyr")
  conflicted::conflict_prefer("select",    "dplyr")
  conflicted::conflict_prefer("summarise", "dplyr")
  conflicted::conflict_prefer("summarize", "dplyr")
  conflicted::conflict_prefer("gather",    "tidyr")
  conflicted::conflict_prefer("set_names", "purrr")
  conflicted::conflict_prefer("plan",      "drake")
}

# Environment defaults
setup_environment_defaults <- function() {
  # Set default environment variables if not already set
  Sys.setenv(
    OMP_NUM_THREADS = Sys.getenv("OMP_NUM_THREADS", "1"),
    OPENBLAS_NUM_THREADS = Sys.getenv("OPENBLAS_NUM_THREADS", "1"),
    MKL_NUM_THREADS = Sys.getenv("MKL_NUM_THREADS", "1"),
    VECLIB_MAXIMUM_THREADS = Sys.getenv("VECLIB_MAXIMUM_THREADS", "1"),
    NUMEXPR_NUM_THREADS = Sys.getenv("NUMEXPR_NUM_THREADS", "1"),
    MC_WORKER_THREADS = Sys.getenv("MC_WORKER_THREADS", "1")
  )
}

# Global options
setup_global_options <- function() {
  # Table formatting (only if flextable is loaded)
  if (requireNamespace("flextable", quietly = TRUE)) {
    flextable::set_flextable_defaults(theme_fun = "theme_box")
  }
  
  # Rounding specifications (only if table.glue is loaded)
  if (requireNamespace("table.glue", quietly = TRUE)) {
    rspec <- table.glue::round_spec() %>%
      table.glue::round_using_magnitude(
        breaks = c(10, 100, Inf),
        digits = c(2, 1, 0)
      )
    names(rspec) <- paste("table.glue", names(rspec), sep = ".")
    options(rspec)
  }
  
  # Parallel processing defaults
  options(future.globals.maxSize = 4 * 1024^3)  # 4GB max object size
}

# Main initialization function
initialize_pipeline <- function(load_functions = TRUE, minimal_packages = FALSE, quiet = TRUE) {
  if (!quiet) message("Initializing graft loss pipeline...")
  
  # Smart package loading
  load_core_packages(minimal = minimal_packages, quiet = quiet)
  setup_conflict_preferences()
  setup_environment_defaults()
  setup_global_options()
  
  if (load_functions) {
    # Load all R utility functions
    r_files <- list.files(here("R"), pattern = "\\.R$", full.names = TRUE)
    lapply(r_files, source)
    if (!quiet) message(sprintf("Loaded %d utility functions from R/", length(r_files)))
  }
  
  if (!quiet) message("Pipeline initialization complete.")
}