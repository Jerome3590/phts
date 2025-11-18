##' Central configuration management for graft loss pipeline
##' 
##' This module handles:
##' - Package loading with conflict resolution
##' - Environment variable defaults
##' - Global options and settings
##' - Path configurations

# Core package loading - simplified without xgboost.surv and obliqueRSF
load_core_packages <- function(minimal = FALSE, force_check = FALSE, quiet = TRUE) {
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

# Global options
setup_global_options <- function() {
  # Table formatting (only if flextable is loaded)
  if (requireNamespace("flextable", quietly = TRUE)) {
    flextable::set_flextable_defaults(theme_fun = "theme_box")
  }
  
  # Rounding specifications (only if table.glue is loaded)
  if (requireNamespace("table.glue", quietly = TRUE)) {
    rspec <- table.glue::round_spec()
    rspec <- table.glue::round_using_magnitude(
      rspec,
      breaks = c(10, 100, Inf),
      digits = c(2, 1, 0)
    )
    names(rspec) <- paste("table.glue", names(rspec), sep = ".")
    options(rspec)
  }
  
  # Set default options for parallel processing
  options(
    future.globals.maxSize = 500 * 1024^2,  # 500MB
    future.fork.enable = TRUE,
    future.resolve.recursive = TRUE
  )
}

# Environment variable defaults
setup_environment_defaults <- function() {
  # Set default environment variables if not already set
  defaults <- list(
    MC_PLAN = "multisession",
    MC_SPLIT_WORKERS = "4",
    MC_WORKER_THREADS = "1",
    OMP_NUM_THREADS = "1",
    MKL_NUM_THREADS = "1",
    OPENBLAS_NUM_THREADS = "1",
    NUMEXPR_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1",
    # EC2-specific settings
    TMPDIR = "/tmp",
    R_TMPDIR = "/tmp"
  )
  
  for (var in names(defaults)) {
    if (Sys.getenv(var) == "") {
      do.call(Sys.setenv, setNames(list(defaults[[var]]), var))
    }
  }
  
  # Ensure temp directory exists and is writable
  temp_dir <- Sys.getenv("TMPDIR", "/tmp")
  
  # Try multiple temp directory options for EC2
  temp_options <- c(
    temp_dir,
    "/tmp",
    "/var/tmp",
    file.path(Sys.getenv("HOME"), "tmp"),
    file.path(getwd(), "tmp")
  )
  
  temp_created <- FALSE
  for (temp_option in temp_options) {
    tryCatch({
      if (!dir.exists(temp_option)) {
        dir.create(temp_option, recursive = TRUE, mode = "0755")
      }
      # Test if we can write to it
      test_file <- file.path(temp_option, "test_write.tmp")
      writeLines("test", test_file)
      unlink(test_file)
      Sys.setenv(TMPDIR = temp_option)
      Sys.setenv(R_TMPDIR = temp_option)
      temp_created <- TRUE
      cat(sprintf("[EC2] Using temp directory: %s\n", temp_option))
      break
    }, error = function(e) {
      # Try next option
    })
  }
  
  if (!temp_created) {
    warning("Could not create writable temp directory, using default")
  }
}

# Package loading function
load_pipeline_packages <- function(minimal = FALSE, quiet = TRUE) {
  # Core packages (always loaded)
  core_packages <- c(
    "here", "dplyr", "tidyr", "purrr", "readr", "tibble", "glue",
    "survival", "aorsf", "riskRegression", "recipes", "rsample",
    "furrr", "future", "conflicted", "janitor", "haven", "naniar", "stringr"
  )
  
  # Note: CatBoost requires special installation and loading
  # It's loaded separately when needed rather than as a core package
  
  # Additional packages (loaded unless minimal = TRUE)
  additional_packages <- c(
    "ggplot2", "plotly", "flextable", "pROC", "survminer",
    "prodlim", "cmprsk", "MASS", "Hmisc", "table.glue"
  )
  
  packages_to_load <- if (minimal) core_packages else c(core_packages, additional_packages)
  
  # Load packages with error handling for EC2 (no installation)
  for (pkg in packages_to_load) {
    tryCatch({
      if (!requireNamespace(pkg, quietly = TRUE)) {
        if (!quiet) cat(sprintf("Warning: Package %s not available (skipping installation)\n", pkg))
      } else {
        library(pkg, character.only = TRUE, quietly = TRUE)
        if (!quiet) cat(sprintf("✓ %s loaded\n", pkg))
      }
    }, error = function(e) {
      if (!quiet) cat(sprintf("Error loading %s: %s\n", pkg, e$message))
    })
  }
}

# Main initialization function
initialize_pipeline <- function(load_functions = TRUE, minimal_packages = FALSE, quiet = TRUE) {
  if (!quiet) message("Initializing graft loss pipeline...")
  
  # Set options to prevent automatic package installation
  options(
    repos = c(CRAN = "https://cloud.r-project.org"),
    install.packages.check.source = "no",
    install.packages.compile.from.source = "never"
  )
  
  # Load packages
  load_core_packages(minimal = minimal_packages, quiet = quiet)
  setup_conflict_preferences()
  setup_environment_defaults()
  setup_global_options()
  
  if (load_functions) {
    # Load all R utility functions
    r_files <- list.files(here("scripts", "R"), pattern = "\\.R$", full.names = TRUE)
    
    # Exclude config.R, install.R, plan.R, and backup/demo files to avoid circular sourcing and unwanted installations
    exclude_patterns <- c(
      "^config", "^install", "^plan", "run_pipeline",  # Core exclusions (run_pipeline is in pipeline/ not scripts/R/)
      "backup", "environment_setup", "install_backup",  # Backup files
      "_demo", "_backup", "setup_demo",  # Demo files
      "reset_package", "validate_fixes", "ec2_",  # Utility files
      "^test_", "^show_progress", "^resource_monitor",  # Test/diagnostic files (not needed for pipeline execution)
      "enhanced_pipeline", "diagnose_cores", "check_versions",  # Diagnostic files
      "aorsf_setup", "ranger_setup", "xgboost_setup", "catboost_setup",  # Setup demo files
      "04_fit_model_fixed", "04_fit_model_main"  # Exclude main pipeline scripts to prevent circular sourcing
    )
    
    # Build regex pattern - use word boundaries for better matching
    exclude_regex <- paste0("(", paste(exclude_patterns, collapse = "|"), ")")
    
    # Filter out excluded files
    r_files_filtered <- r_files[!grepl(exclude_regex, basename(r_files))]
    
    # Additionally filter out files that don't exist (defensive check)
    r_files_filtered <- r_files_filtered[file.exists(r_files_filtered)]
    
    # DEBUG: List files being sourced
    if (!quiet) {
      excluded_count <- length(r_files) - length(r_files_filtered)
      if (excluded_count > 0) {
        message(sprintf("Excluded %d utility files (config, tests, demos, etc.)", excluded_count))
      }
      message(sprintf("Loading %d utility functions from scripts/R/", length(r_files_filtered)))
    }
    
    # Source files one by one with error handling
    sourced_count <- 0
    for (i in seq_along(r_files_filtered)) {
      tryCatch({
        source(r_files_filtered[i])
        sourced_count <- sourced_count + 1
      }, error = function(e) {
        # For any sourcing errors, report them clearly
        error_msg <- e$message
        
        # Check if this is a known non-critical pattern
        skip_patterns <- c("RStudio not running", "rstudioapi")
        is_skippable <- any(sapply(skip_patterns, function(pattern) {
          grepl(pattern, error_msg, ignore.case = TRUE)
        }))
        
        if (is_skippable) {
          if (!quiet) {
            message(sprintf("⚠ Skipped %s (requires RStudio)", basename(r_files_filtered[i])))
          }
          return(NULL)
        }
        
        # For critical errors, provide detailed information
        message(sprintf("✗ ERROR sourcing %s: %s", basename(r_files_filtered[i]), error_msg))
        message(sprintf("Full path: %s", r_files_filtered[i]))
        stop(sprintf("Failed to source required utility file: %s", basename(r_files_filtered[i])))
      })
    }
    
    if (!quiet) message(sprintf("✓ Successfully loaded %d utility functions", sourced_count))
  }
  
  if (!quiet) message("Pipeline initialization complete.")
}
