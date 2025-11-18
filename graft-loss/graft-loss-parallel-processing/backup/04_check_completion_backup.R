#!/usr/bin/env Rscript

# 04_check_completion.R
# Check completion status of all three cohorts processing


suppressPackageStartupMessages({
  library(furrr)
  library(purrr)
  library(withr)
  library(fs)
  library(tibble)
})

# Set number of threads per worker for max CPU utilization
threads_per_worker <- 8  # Adjust as needed for your instance
Sys.setenv(
  OMP_NUM_THREADS = as.character(threads_per_worker),
  MKL_NUM_THREADS = as.character(threads_per_worker),
  OPENBLAS_NUM_THREADS = as.character(threads_per_worker),
  NUMEXPR_NUM_THREADS = as.character(threads_per_worker),
  VECLIB_MAXIMUM_THREADS = as.character(threads_per_worker)
)

cohorts <- list(
    original = list(
      env = list(DATASET_COHORT = "original"),
      log = file.path(getwd(), "logs/orch_bg_original_study.log")
    ),
    full_with_covid = list(
      env = list(DATASET_COHORT = "full_with_covid"), 
      log = file.path(getwd(), "logs/orch_bg_full_with_covid.log")
    ),
    full_without_covid = list(
      env = list(DATASET_COHORT = "full_without_covid"),
      log = file.path(getwd(), "logs/orch_bg_full_without_covid.log")
    )
  )

# Load split indices globally for all steps
# Robust reader that tries several formats before giving up
read_compat_rds <- function(path) {
  stopifnot(is.character(path), length(path) == 1)

  # 1) Try plain RDS (fast path)
  out <- try(readRDS(path), silent = TRUE)
  if (!inherits(out, "try-error")) return(out)

  # 2) Detect gzip header and try gzipped RDS
  con <- file(path, "rb")
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  head2 <- try(readBin(con, "raw", 2), silent = TRUE)
  if (!inherits(head2, "try-error") && length(head2) == 2 &&
      identical(head2, as.raw(c(0x1f, 0x8b)))) {
    # gzip header found
    seek(con, 0)
    gz <- gzcon(con)
    out <- try(readRDS(gz), silent = TRUE)
    try(close(gz), silent = TRUE)
    if (!inherits(out, "try-error")) return(out)
  }
  try(close(con), silent = TRUE)

  # 3) Maybe it's an .RData/.rda saved with save()
  env <- new.env(parent = emptyenv())
  ld <- try(load(path, envir = env), silent = TRUE)
  if (!inherits(ld, "try-error") && length(ld) > 0) {
    # If multiple objects, return a named list
    return(mget(ld, envir = env, inherits = FALSE))
  }

  # 4) Maybe it’s a qs file (fast serialization)
  if (requireNamespace("qs", quietly = TRUE)) {
    out <- try(qs::qread(path), silent = TRUE)
    if (!inherits(out, "try-error")) return(out)
  }

  # 5) Still failing? - Provide an actionable error with next steps
  rv <- as.character(getRversion())
  stop(sprintf(
    paste0(
      "Could not read '%s'. Tried: readRDS, gzipped RDS, load(.RData), qs::qread.\n",
      "Most likely cause: the file was written by a newer R than your session (%s).\n",
      "Fix on a machine that CAN read it:\n",
      "  obj <- readRDS('%s'); saveRDS(obj, '%s.v2.rds', version = 2)\n",
      "…then use the .v2.rds on this machine. Alternatively, upgrade R here."
    ),
    path, rv, path, path
  ))
}


# Generic runner for local-only steps with proper orch_bg_* logging
run_step_local <- function(step_label, script_rel, cohorts, workers = NULL, seed = TRUE) {
  root <- getwd()
  step_script <- file.path(root, script_rel)
  if (!file.exists(step_script)) stop(sprintf("Script not found: %s", step_script))

  # Forked workers for Linux + local IO
  if (is.null(workers)) workers <- max(1, min(3, parallel::detectCores() - 1))
  plan(multicore, workers = workers)

  on.exit(plan(sequential), add = TRUE)

  results <- future_map(
    names(cohorts),
    function(cohort) {
      cfg <- cohorts[[cohort]]
      env_vars <- c(cfg$env, COHORT_NAME = cohort)
      log_file <- cfg$log

      tryCatch({
        old_wd <- setwd(root); on.exit(setwd(old_wd), add = TRUE)
        
        # Create/ensure log directory exists
        log_dir <- dirname(log_file)
        dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
        
        # Enhanced logging function
        log_with_resources <- function(message, step = step_label) {
          timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
          pid <- Sys.getpid()
          
          # Memory usage
          mem_info <- tryCatch({
            if (file.exists("/proc/meminfo")) {
              meminfo <- readLines("/proc/meminfo")
              total_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemTotal", meminfo)])) / 1024 / 1024
              avail_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemAvailable", meminfo)])) / 1024 / 1024
              used_mem <- total_mem - avail_mem
              sprintf("MEM: %.1f/%.1f GB (%.1f%%)", used_mem, total_mem, (used_mem/total_mem)*100)
            } else {
              gc_info <- gc()
              sprintf("MEM: %.1f MB", sum(gc_info[,2]))
            }
          }, error = function(e) "MEM: N/A")
          
          # CPU usage
          cpu_info <- tryCatch({
            if (Sys.which("ps") != "") {
              ps_out <- system(sprintf("ps -p %d -o pcpu= 2>/dev/null || echo 'N/A'", pid), intern = TRUE)
              if (length(ps_out) > 0 && ps_out != "N/A") {
                sprintf("CPU: %s%%", trimws(ps_out))
              } else "CPU: N/A"
            } else "CPU: N/A"
          }, error = function(e) "CPU: N/A")
          
          # Format log entry
          step_info <- if (!is.null(step)) sprintf("[STEP: %s] ", step) else ""
          log_entry <- sprintf("[%s] [%s] %s| %s | %s | %s", 
                              timestamp, cohort, step_info, mem_info, cpu_info, message)
          
          # Write to both console and log file
          cat(log_entry, "\n")
          cat(log_entry, "\n", file = log_file, append = TRUE)
        }
        
        # Log step start
        log_with_resources(sprintf("Starting %s", step_label))

        msgs <- character(); wns <- character()
        t0 <- proc.time()
        
        # Capture output and write to log
        output_conn <- file(log_file, open = "a")
        sink(output_conn, split = TRUE)
        sink(output_conn, type = "message", append = TRUE)
        
        on.exit({
          try(sink(type = "message"))
          try(sink())
          try(close(output_conn))
        }, add = TRUE)
        
        withCallingHandlers(
          {
            with_envvar(env_vars, {
              source(step_script, local = new.env(parent = globalenv()))
            })
          },
          message = function(m) msgs <<- c(msgs, conditionMessage(m)),
          warning = function(w) wns  <<- c(wns,  conditionMessage(w))
        )
        elapsed <- as.numeric((proc.time() - t0)[["elapsed"]])
        
        # Log completion
        log_with_resources(sprintf("Completed %s (%.2f seconds)", step_label, elapsed))

        tail_lines <- if (file.exists(log_file)) {
          tryCatch(utils::tail(readLines(log_file, warn = FALSE), 10),
                   error = function(e) sprintf("<could not read log: %s>", e$message))
        } else {
          "<log file not found; run pipeline to generate logs>"
        }

        list(
          cohort   = cohort,
          step     = step_label,
          status   = "ok",
          runtime_s = elapsed,
          warnings = wns,
          messages = msgs,
          log_path = log_file,
          log_tail = tail_lines,
          error    = NULL
        )
      }, error = function(e) {
        # Log error
        tryCatch({
          log_with_resources(sprintf("ERROR in %s: %s", step_label, conditionMessage(e)))
        }, error = function(e2) {
          # Fallback if logging fails
          cat(sprintf("ERROR in %s: %s\n", step_label, conditionMessage(e)), file = log_file, append = TRUE)
        })
        
        list(
          cohort   = cohort,
          step     = step_label,
          status   = "error",
          runtime_s = NA_real_,
          warnings = NULL,
          messages = NULL,
          log_path = log_file,
          log_tail = NULL,
          error    = conditionMessage(e)
        )
      })
    },
    .options = furrr_options(seed = isTRUE(seed))
  )

  # Print concise summary and also return a tibble of results
  cat(sprintf("\n==== Batch Summary (%s) ====\n", step_label))
  walk(results, function(r) {
    cat(sprintf("\n--- %s ---\n", r$cohort))
    cat(sprintf("Status: %s\n", r$status))
    if (!is.null(r$error))   cat(sprintf("Error: %s\n", r$error))
    if (!is.na(r$runtime_s)) cat(sprintf("Runtime (s): %.2f\n", r$runtime_s))
    if (length(r$warnings))  cat(sprintf("Warnings: %s\n", paste(r$warnings, collapse = " | ")))
    if (length(r$messages))  cat(sprintf("Messages: %s\n", paste(r$messages, collapse = " | ")))
    cat(sprintf("Log: %s\n", r$log_path))
    if (!is.null(r$log_tail)) {
      cat("--- Last 10 log lines ---\n")
      cat(paste0(r$log_tail, collapse = "\n"), "\n")
    }
  })
  cat("\n=======================\n")

  # Return structured data for programmatic checks
  as_tibble(map_dfr(results, ~as.list(.x)[c("cohort","step","status","runtime_s","error","log_path")]))
}

# Diagnostic output for debugging parallel execution and logging
cat("\n[04_check_completion.R] Starting completion check script\n")
cat("Cohort env variable: ", Sys.getenv("DATASET_COHORT", unset = "<unset>"), "\n")
cat("Working directory: ", getwd(), "\n")

# Determine log file based on cohort
log_file <- switch(Sys.getenv("DATASET_COHORT", unset = ""),
  original = "logs/orch_bg_original_study.log",
  full_with_covid = "logs/orch_bg_full_with_covid.log", 
  full_without_covid = "logs/orch_bg_full_without_covid.log",
  "logs/orch_bg_unknown.log"
)
cat("Log file path: ", log_file, "\n")
cat("[04_check_completion.R] Diagnostic output complete\n\n")

# =============================================================================
# LOGGING SETUP
# =============================================================================

# Create logs directory if it doesn't exist
if (!dir.exists("logs")) {
  dir.create("logs", showWarnings = FALSE, recursive = TRUE)
}

# Set up completion check log file
completion_log_file <- file.path("logs", sprintf("completion_check_%s.log", format(Sys.time(), "%Y%m%d_%H%M%S")))

# Redirect output to both console and log file
log_conn <- file(completion_log_file, open = 'at')
sink(log_conn, split = TRUE)
sink(log_conn, type = 'message', append = TRUE)

# Set up cleanup on exit
on.exit({
  try(sink(type = 'message'))
  try(sink())
  try(close(log_conn))
}, add = TRUE)

cat("=== Completion Check Logging Setup ===\n")
cat("Completion log file:", completion_log_file, "\n")
cat("Timestamp:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# =============================================================================
# COMPLETION CHECK LOGIC
# =============================================================================

cat("=== Cohort Processing Status Check ===\n")
cat("Timestamp:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Current cohort:", Sys.getenv("DATASET_COHORT", unset = "unknown"), "\n\n")

# Define all cohorts and their log files
all_cohorts <- c("original", "full_with_covid", "full_without_covid")
all_log_files <- c(
  "logs/orch_bg_original_study.log",
  "logs/orch_bg_full_with_covid.log", 
  "logs/orch_bg_full_without_covid.log"
)

# Function to find the actual log file (handles .log/.txt extension mismatch)
find_log_file <- function(base_name) {
  # Try .log first (preferred)
  log_file <- paste0(base_name, ".log")
  if (file.exists(log_file)) {
    cat(sprintf("[DEBUG] Found .log file: %s\n", log_file))
    return(log_file)
  }
  
  # Fallback to .txt (download conversion)
  txt_file <- paste0(base_name, ".txt")
  if (file.exists(txt_file)) {
    cat(sprintf("[DEBUG] Found .txt file (download conversion): %s\n", txt_file))
    return(txt_file)
  }
  
  # Return original if neither exists
  cat(sprintf("[DEBUG] No log file found for: %s\n", base_name))
  return(log_file)
}

# Check each cohort
all_completed <- TRUE
current_cohort <- Sys.getenv("DATASET_COHORT", unset = "unknown")

for (i in seq_along(all_cohorts)) {
  cohort <- all_cohorts[i]
  cohort_log <- find_log_file(gsub("\\.log$", "", all_log_files[i]))
  
  # Highlight current cohort
  prefix <- if (cohort == current_cohort) ">>> " else "    "
  cat(sprintf("%sCohort: %s\n", prefix, cohort))
  
  if (file.exists(cohort_log)) {
    # Get file info
    info <- file.info(cohort_log)
    cat(sprintf("%s  Log file: %s (%.1f MB)\n", prefix, cohort_log, info$size / 1024 / 1024))
    cat(sprintf("%s  Last modified: %s\n", prefix, format(info$mtime, "%Y-%m-%d %H:%M:%S")))
    
    # Check for completion indicators in last 50 lines
    lines <- tryCatch(tail(readLines(cohort_log, warn = FALSE), 50), error = function(e) character(0))
    
    completed <- any(grepl("completed successfully|Completed Successfully|Pipeline.*[Cc]ompleted", lines, ignore.case = TRUE))
    failed <- any(grepl("ERROR|FAILED|error in", lines, ignore.case = TRUE))
    
    if (completed) {
      cat(sprintf("%s  Status: ✅ COMPLETED\n", prefix))
    } else if (failed) {
      cat(sprintf("%s  Status: ❌ FAILED (check log for details)\n", prefix))
      all_completed <- FALSE
    } else {
      cat(sprintf("%s  Status: 🔄 RUNNING (or incomplete)\n", prefix))
      all_completed <- FALSE
    }
  } else {
    cat(sprintf("%s  Log file: ❌ NOT FOUND\n", prefix))
    cat(sprintf("%s  Status: ❓ NOT STARTED\n", prefix))
    all_completed <- FALSE
  }
  cat("\n")
}

# Overall status
if (all_completed) {
  cat("🎉 ALL THREE COHORTS COMPLETED SUCCESSFULLY! 🎉\n")
} else {
  cat("⏳ Some cohorts are still processing or failed. Check individual logs.\n")
}

# Check for R processes (Linux compatible)
r_processes <- tryCatch({
  if (.Platform$OS.type == "unix") {
    # Linux/Mac: Use pgrep with proper error handling
    result <- system("pgrep -c '^(R|Rscript)$' 2>/dev/null", intern = TRUE, ignore.stderr = TRUE)
    if (length(result) > 0 && !is.na(suppressWarnings(as.numeric(result)))) {
      as.character(result)
    } else {
      # Fallback: use ps and grep
      result2 <- system("ps aux | grep -E '(^|/)R(script)?( |$)' | grep -v grep | wc -l 2>/dev/null", intern = TRUE, ignore.stderr = TRUE)
      if (length(result2) > 0 && !is.na(suppressWarnings(as.numeric(result2)))) {
        as.character(result2)
      } else {
        "0"
      }
    }
  } else {
    # Windows: Use tasklist to count R processes
    result <- system('tasklist /FI "IMAGENAME eq Rscript.exe" /FO CSV 2>nul | find /C "Rscript.exe"', intern = TRUE, ignore.stderr = TRUE)
    if (length(result) > 0 && !is.na(suppressWarnings(as.numeric(result)))) {
      as.character(result)
    } else {
      "0"
    }
  }
}, error = function(e) {
  cat(sprintf("Note: Could not check R processes (%s)\n", e$message))
  "unknown"
})

cat(sprintf("\nActive R processes: %s\n", r_processes))

# Check model output files by cohort
cat("\nModel output files by cohort:\n")
cohorts_for_models <- c("original", "full_with_covid", "full_without_covid")

for (cohort in cohorts_for_models) {
  # Highlight current cohort
  prefix <- if (cohort == current_cohort) ">>> " else "    "
  cat(sprintf("%s%s cohort:\n", prefix, cohort))
  
  # Check MC-CV split models
  models_dir <- file.path("models", cohort)
  if (dir.exists(models_dir)) {
    mc_models <- list.files(models_dir, pattern = "*_split[0-9]+\\.rds$", full.names = TRUE)
    if (length(mc_models) > 0) {
      cat(sprintf("%s  MC-CV split models: %d files\n", prefix, length(mc_models)))
      # Show breakdown by model type
      orsf_count <- length(grep("ORSF_split", mc_models))
      rsf_count <- length(grep("RSF_split", mc_models))
      xgb_count <- length(grep("XGB_split", mc_models))
      cph_count <- length(grep("CPH_split", mc_models))
      cat(sprintf("%s    ORSF: %d, RSF: %d, XGB: %d, CPH: %d\n", prefix, orsf_count, rsf_count, xgb_count, cph_count))
      
      # Show expected vs actual counts
      expected_per_model <- as.integer(Sys.getenv("MC_TIMES", "1000"))  # MC-CV splits (from MC_TIMES environment variable)
      if (orsf_count > 0 || rsf_count > 0 || xgb_count > 0 || cph_count > 0) {
        cat(sprintf("%s    Expected per model: %d splits\n", prefix, expected_per_model))
        if (orsf_count < expected_per_model) cat(sprintf("%s    ⚠️  ORSF incomplete: %d/%d\n", prefix, orsf_count, expected_per_model))
        if (rsf_count < expected_per_model) cat(sprintf("%s    ⚠️  RSF incomplete: %d/%d\n", prefix, rsf_count, expected_per_model))
        if (xgb_count < expected_per_model) cat(sprintf("%s    ⚠️  XGB incomplete: %d/%d\n", prefix, xgb_count, expected_per_model))
        if (cph_count < expected_per_model) cat(sprintf("%s    ⚠️  CPH incomplete: %d/%d\n", prefix, cph_count, expected_per_model))
      }
    } else {
      cat(sprintf("%s  MC-CV split models: None found\n", prefix))
    }
    
    # Check final models
    final_models <- list.files(models_dir, pattern = "^(final_model|model_(orsf|rsf|xgb|cph))\\.rds$", full.names = TRUE)
    if (length(final_models) > 0) {
      cat(sprintf("%s  Final models: %d files\n", prefix, length(final_models)))
      for (fm in basename(final_models)) {
        file_size <- file.size(file.path(models_dir, fm)) / 1024 / 1024
        cat(sprintf("%s    %s (%.1f MB)\n", prefix, fm, file_size))
      }
    } else {
      cat(sprintf("%s  Final models: None found\n", prefix))
    }
    
    # Check other important files
    other_files <- c("model_comparison_index.csv", "model_comparison_metrics.csv", "final_model_choice.csv", "split_indices.rds")
    found_other <- character(0)
    for (of in other_files) {
      if (file.exists(file.path(models_dir, of))) {
        found_other <- c(found_other, of)
      }
    }
    if (length(found_other) > 0) {
      cat(sprintf("%s  Other files: %s\n", prefix, paste(found_other, collapse = ", ")))
    }
    
  } else {
    cat(sprintf("%s  Models directory: Not found (%s)\n", prefix, models_dir))
  }
  
  # Check legacy data/models cohort directory
  data_models_dir <- file.path("data", "models", cohort)
  if (dir.exists(data_models_dir)) {
    data_models <- list.files(data_models_dir, pattern = "\\.rds$", full.names = TRUE)
    if (length(data_models) > 0) {
      cat(sprintf("%s  Legacy data models: %d files (old XGB location)\n", prefix, length(data_models)))
    }
  }
}

# Check for any models in old locations (not cohort-specific)
old_models <- list.files("models", pattern = "*.rds", full.names = TRUE)
old_models <- old_models[!grepl("/(original|full_with_covid|full_without_covid)/", old_models)]
if (length(old_models) > 0) {
  cat(sprintf("\n  ⚠️  Models in old location (not cohort-specific): %d files\n", length(old_models)))
  cat("    These may be from previous runs or need to be moved\n")
}

# Summary for current cohort
cat(sprintf("\n=== Summary for Current Cohort (%s) ===\n", current_cohort))
current_log <- switch(current_cohort,
  original = find_log_file("logs/orch_bg_original_study"),
  full_with_covid = find_log_file("logs/orch_bg_full_with_covid"),
  full_without_covid = find_log_file("logs/orch_bg_full_without_covid"),
  find_log_file("logs/orch_bg_unknown")
)

if (file.exists(current_log)) {
  cat("Last 5 lines from current cohort log:\n")
  recent_lines <- tryCatch(tail(readLines(current_log, warn = FALSE), 5), error = function(e) "Could not read log")
  for (line in recent_lines) {
    cat("  ", line, "\n")
  }
} else {
  cat("Current cohort log not found\n")
}

cat("\n=== End Status Check ===\n")
cat("Completion check log saved to:", completion_log_file, "\n")
cat("Completion check finished at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")

# Return appropriate exit code
if (all_completed) {
  cat("\n[SUCCESS] All cohorts completed successfully\n")
  quit(status = 0)
} else {
  cat("\n[INFO] Some cohorts still processing or incomplete\n") 
  quit(status = 0)  # Don't fail the pipeline, just report status
}