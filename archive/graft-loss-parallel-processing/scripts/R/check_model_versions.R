##' Check versions of all model libraries used in the pipeline
##' 
##' @param include_r_info Whether to include R version information (default: TRUE)
##' @param include_system_info Whether to include system information (default: TRUE)
##' @return List with version information for all model libraries
check_model_versions <- function(include_r_info = TRUE, include_system_info = TRUE) {
  
  # Core model libraries
  model_packages <- c(
    "ranger",           # Random Survival Forest
    "aorsf",           # Oblique Random Survival Forest
    "survival",        # Survival analysis
    "riskRegression",  # Risk prediction
    "prodlim",         # Product limit estimation
    "recipes",         # Data preprocessing
    "rsample",         # Resampling
    "dplyr",           # Data manipulation
    "tibble",          # Data frames
    "glue",            # String interpolation
    "here",            # Path management
    "furrr",           # Parallel processing
    "future"           # Parallel processing backend
  )
  
  # Initialize results
  versions <- list()
  
  # Add R version information
  if (include_r_info) {
    versions$r_info <- list(
      r_version_string = R.version.string,
      r_version_numeric = as.character(getRversion()),
      r_platform = R.version$platform,
      r_arch = R.version$arch,
      r_os = R.version$os
    )
  }
  
  # Add system information
  if (include_system_info) {
    versions$system_info <- list(
      available_cores = tryCatch({
        if (requireNamespace("future", quietly = TRUE)) {
          as.numeric(future::availableCores())
        } else {
          parallel::detectCores(logical = TRUE)
        }
      }, error = function(e) "Unknown"),
      memory_limit = tryCatch({
        if (.Platform$OS.type == "windows") {
          memory.limit()
        } else {
          "N/A (Unix/Linux)"
        }
      }, error = function(e) "Unknown"),
      working_directory = getwd(),
      temp_directory = tempdir()
    )
  }
  
  # Check each model package
  versions$packages <- list()
  
  for (pkg in model_packages) {
    versions$packages[[pkg]] <- list(
      loaded = requireNamespace(pkg, quietly = TRUE),
      version = if (requireNamespace(pkg, quietly = TRUE)) {
        as.character(packageVersion(pkg))
      } else {
        "Not installed"
      },
      installed = pkg %in% rownames(installed.packages()),
      path = if (pkg %in% rownames(installed.packages())) {
        tryCatch({
          system.file(package = pkg)
        }, error = function(e) "Unknown")
      } else {
        "Not installed"
      }
    )
  }
  
  # Add environment variables relevant to model libraries
  versions$environment_vars <- list(
    # Ranger
    R_RANGER_NUM_THREADS = Sys.getenv("R_RANGER_NUM_THREADS", unset = "Not set"),
    # OpenMP
    OMP_NUM_THREADS = Sys.getenv("OMP_NUM_THREADS", unset = "Not set"),
    # BLAS/LAPACK
    MKL_NUM_THREADS = Sys.getenv("MKL_NUM_THREADS", unset = "Not set"),
    OPENBLAS_NUM_THREADS = Sys.getenv("OPENBLAS_NUM_THREADS", unset = "Not set"),
    VECLIB_MAXIMUM_THREADS = Sys.getenv("VECLIB_MAXIMUM_THREADS", unset = "Not set"),
    NUMEXPR_NUM_THREADS = Sys.getenv("NUMEXPR_NUM_THREADS", unset = "Not set"),
    # XGBoost
    XGBOOST_NUM_THREADS = Sys.getenv("XGBOOST_NUM_THREADS", unset = "Not set"),
    # Parallel processing
    MC_WORKER_THREADS = Sys.getenv("MC_WORKER_THREADS", unset = "Not set"),
    # Model-specific
    RSF_NTREES = Sys.getenv("RSF_NTREES", unset = "Not set"),
    ORSF_NTREES = Sys.getenv("ORSF_NTREES", unset = "Not set"),
    XGB_NTREES = Sys.getenv("XGB_NTREES", unset = "Not set")
  )
  
  # Add R options relevant to model libraries
  versions$r_options <- list(
    ranger.num.threads = getOption("ranger.num.threads", "Not set"),
    Ncpus = getOption("Ncpus", "Not set"),
    mc.cores = getOption("mc.cores", "Not set"),
    future.plan = tryCatch({
      if (requireNamespace("future", quietly = TRUE)) {
        as.character(future::plan())
      } else {
        "future not loaded"
      }
    }, error = function(e) "Unknown")
  )
  
  return(versions)
}

##' Print model library versions in a formatted way
##' 
##' @param versions Version information object (from check_model_versions)
##' @param show_loaded_only Whether to show only loaded packages (default: FALSE)
##' @param show_system_info Whether to show system information (default: TRUE)
print_model_versions <- function(versions = NULL, show_loaded_only = FALSE, show_system_info = TRUE) {
  
  if (is.null(versions)) {
    versions <- check_model_versions()
  }
  
  cat("=== MODEL LIBRARY VERSIONS ===\n")
  
  # R version information
  if (!is.null(versions$r_info)) {
    cat("\n--- R Version ---\n")
    cat(sprintf("R Version: %s\n", versions$r_info$r_version_string))
    cat(sprintf("R Numeric: %s\n", versions$r_info$r_version_numeric))
    cat(sprintf("Platform: %s\n", versions$r_info$r_platform))
    cat(sprintf("Architecture: %s\n", versions$r_info$r_arch))
    cat(sprintf("OS: %s\n", versions$r_info$r_os))
  }
  
  # System information
  if (show_system_info && !is.null(versions$system_info)) {
    cat("\n--- System Information ---\n")
    cat(sprintf("Available cores: %s\n", versions$system_info$available_cores))
    cat(sprintf("Memory limit: %s\n", versions$system_info$memory_limit))
    cat(sprintf("Working directory: %s\n", versions$system_info$working_directory))
    cat(sprintf("Temp directory: %s\n", versions$system_info$temp_directory))
  }
  
  # Package versions
  cat("\n--- Package Versions ---\n")
  
  # Core model packages
  core_packages <- c("ranger", "aorsf", "survival", "riskRegression")
  cat("\nCore Model Packages:\n")
  for (pkg in core_packages) {
    if (pkg %in% names(versions$packages)) {
      pkg_info <- versions$packages[[pkg]]
      if (!show_loaded_only || pkg_info$loaded) {
        status <- if (pkg_info$loaded) "✓" else if (pkg_info$installed) "○" else "✗"
        cat(sprintf("  %s %-15s: %s %s\n", status, pkg, pkg_info$version, 
                   if (pkg_info$loaded) "(loaded)" else if (pkg_info$installed) "(installed)" else "(not installed)"))
      }
    }
  }
  
  # Utility packages
  utility_packages <- c("recipes", "rsample", "dplyr", "tibble", "glue", "here", "furrr", "future", "prodlim")
  cat("\nUtility Packages:\n")
  for (pkg in utility_packages) {
    if (pkg %in% names(versions$packages)) {
      pkg_info <- versions$packages[[pkg]]
      if (!show_loaded_only || pkg_info$loaded) {
        status <- if (pkg_info$loaded) "✓" else if (pkg_info$installed) "○" else "✗"
        cat(sprintf("  %s %-15s: %s %s\n", status, pkg, pkg_info$version, 
                   if (pkg_info$loaded) "(loaded)" else if (pkg_info$installed) "(installed)" else "(not installed)"))
      }
    }
  }
  
  # Environment variables
  cat("\n--- Environment Variables ---\n")
  for (var in names(versions$environment_vars)) {
    value <- versions$environment_vars[[var]]
    if (value != "Not set") {
      cat(sprintf("  %-25s: %s\n", var, value))
    }
  }
  
  # R options
  cat("\n--- R Options ---\n")
  for (opt in names(versions$r_options)) {
    value <- versions$r_options[[opt]]
    if (value != "Not set" && value != "Unknown") {
      cat(sprintf("  %-25s: %s\n", opt, value))
    }
  }
  
  cat("\n=============================\n")
}

##' Save model library versions to a file
##' 
##' @param file_path Path to save the version information
##' @param versions Version information object (from check_model_versions)
##' @param format Output format ("text", "json", "yaml")
save_model_versions <- function(file_path, versions = NULL, format = "text") {
  
  if (is.null(versions)) {
    versions <- check_model_versions()
  }
  
  if (format == "text") {
    # Capture the printed output
    output <- capture.output(print_model_versions(versions))
    writeLines(output, file_path)
  } else if (format == "json") {
    if (requireNamespace("jsonlite", quietly = TRUE)) {
      jsonlite::write_json(versions, file_path, pretty = TRUE)
    } else {
      stop("jsonlite package required for JSON output")
    }
  } else if (format == "yaml") {
    if (requireNamespace("yaml", quietly = TRUE)) {
      yaml::write_yaml(versions, file_path)
    } else {
      stop("yaml package required for YAML output")
    }
  } else {
    stop("Unsupported format. Use 'text', 'json', or 'yaml'")
  }
  
  cat(sprintf("Version information saved to: %s\n", file_path))
}

##' Check for version compatibility issues
##' 
##' @param versions Version information object (from check_model_versions)
##' @return List of compatibility warnings and recommendations
check_version_compatibility <- function(versions = NULL) {
  
  if (is.null(versions)) {
    versions <- check_model_versions()
  }
  
  warnings <- list()
  recommendations <- list()
  
  # Check R version
  r_version <- as.numeric_version(versions$r_info$r_version_numeric)
  if (r_version < "4.0.0") {
    warnings <- append(warnings, "R version is older than 4.0.0, some packages may not work correctly")
    recommendations <- append(recommendations, "Consider upgrading to R 4.0.0 or later")
  }
  
  # Check critical packages
  critical_packages <- c("ranger", "survival", "riskRegression")
  for (pkg in critical_packages) {
    if (!versions$packages[[pkg]]$loaded) {
      warnings <- append(warnings, sprintf("Critical package '%s' is not loaded", pkg))
      recommendations <- append(recommendations, sprintf("Load package '%s' with library(%s)", pkg, pkg))
    }
  }
  
  # Check for missing packages
  missing_packages <- names(versions$packages)[sapply(versions$packages, function(x) !x$installed)]
  if (length(missing_packages) > 0) {
    warnings <- append(warnings, sprintf("Missing packages: %s", paste(missing_packages, collapse = ", ")))
    recommendations <- append(recommendations, sprintf("Install missing packages: install.packages(c(%s))", 
                                                     paste(sprintf("'%s'", missing_packages), collapse = ", ")))
  }
  
  # Check threading configuration
  if (versions$environment_vars$OMP_NUM_THREADS == "Not set") {
    warnings <- append(warnings, "OMP_NUM_THREADS not set, may cause threading issues")
    recommendations <- append(recommendations, "Set OMP_NUM_THREADS environment variable")
  }
  
  return(list(
    warnings = warnings,
    recommendations = recommendations,
    critical_issues = length(warnings) > 0
  ))
}
