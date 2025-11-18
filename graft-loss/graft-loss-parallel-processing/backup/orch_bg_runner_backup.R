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

  # 5) Still failing — very likely a newer R serialization
  # Provide an actionable error with next steps
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
