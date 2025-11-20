cat("\n\n##############################################\n")
cat(sprintf("### STARTING STEP: 04_furrr_fit_test.R [%s] ###\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("##############################################\n\n")

# Minimal dependencies
suppressPackageStartupMessages({
  library(future)
  library(furrr)
})

# Optional: use ranger for a simple CPU-bound model fit
have_ranger <- requireNamespace("ranger", quietly = TRUE)
if (!have_ranger) {
  stop("Package 'ranger' is required for the test. Please install it and retry.")
}

# Threading control to avoid oversubscription
worker_threads <- suppressWarnings(as.integer(Sys.getenv("MC_WORKER_THREADS", unset = "1")))
if (!is.finite(worker_threads) || worker_threads < 1) worker_threads <- 1L
Sys.setenv(
  OMP_NUM_THREADS = as.character(worker_threads),
  OPENBLAS_NUM_THREADS = as.character(worker_threads),
  MKL_NUM_THREADS = as.character(worker_threads),
  VECLIB_MAXIMUM_THREADS = as.character(worker_threads),
  NUMEXPR_NUM_THREADS = as.character(worker_threads)
)
message(sprintf("Per-worker threads set to %d (MC_WORKER_THREADS)", worker_threads))

# Determine workers
avail <- tryCatch(as.numeric(future::availableCores()), error = function(e) parallel::detectCores(logical = TRUE))
workers_env <- suppressWarnings(as.integer(Sys.getenv("MC_SPLIT_WORKERS", unset = "0")))
workers <- if (is.finite(workers_env) && workers_env > 0) workers_env else max(1L, floor(avail * 0.80))

cat(sprintf("[TEST] availableCores=%s detectCores(logical)= %s workers=%d\n",
            as.character(avail), parallel::detectCores(logical = TRUE), workers))

# Choose plan: force multisession (works on all OS) for PID visibility
future::plan(future::multisession, workers = workers)
cat("[TEST] Using future::multisession plan\n")

on.exit({
  try(future::plan(sequential), silent = TRUE)
}, add = TRUE)

# Sanity check: PIDs returned by futures
pid_check <- future.apply::future_sapply(1:min(workers, 4L), function(i) Sys.getpid(), future.seed = TRUE)
unique_pids <- unique(as.integer(pid_check))
cat(sprintf("[TEST] sanity future worker PIDs: %s\n", paste(unique_pids, collapse = ", ")))

# Fallback to explicit PSOCK cluster if multisession didn't spawn new PIDs
if (length(unique_pids) <= 1L) {
  cat("[TEST] Fallback: creating explicit PSOCK cluster via parallelly::makeClusterPSOCK\n")
  rscript_bin <- file.path(R.home("bin"), ifelse(.Platform$OS.type == "windows", "Rscript.exe", "Rscript"))
  if (!file.exists(rscript_bin)) rscript_bin <- "Rscript"  # hope it's on PATH
  cl <- parallelly::makeClusterPSOCK(workers, rscript = rscript_bin)
  future::plan(future::cluster, workers = cl)
  parallel::clusterCall(cl, function() { suppressPackageStartupMessages(library(ranger)); NULL })
  pid_check <- future.apply::future_sapply(1:min(workers, 4L), function(i) Sys.getpid(), future.seed = TRUE)
  unique_pids <- unique(as.integer(pid_check))
  cat(sprintf("[TEST] PSOCK sanity worker PIDs: %s\n", paste(unique_pids, collapse = ", ")))
}

# Simple parallel test: fit ranger on mtcars multiple times
fit_one <- function(k) {
  pid <- Sys.getpid()
  t0 <- Sys.time()
  invisible(ranger::ranger(mpg ~ ., data = mtcars, num.trees = 2000,
                           write.forest = FALSE,
                           num.threads = as.integer(Sys.getenv("OMP_NUM_THREADS", unset = "1"))))
  t1 <- Sys.time()
  elapsed <- as.numeric(difftime(t1, t0, units = "secs"))
  cat(sprintf("[TEST] k=%d PID=%s elapsed=%.2fs\n", k, pid, elapsed))
  list(k = k, pid = pid, elapsed = elapsed)
}

n_jobs_env <- suppressWarnings(as.integer(Sys.getenv("TEST_JOBS", unset = "min")))
if (is.na(n_jobs_env)) n_jobs_env <- "min"
n_jobs <- if (identical(n_jobs_env, "min")) max(2L, min(workers * 2L, 8L)) else max(1L, n_jobs_env)

cat(sprintf("[TEST] Launching %d parallel jobs with worker_threads=%d\n", n_jobs, worker_threads))

res_list <- as.list(future.apply::future_lapply(
  seq_len(n_jobs),
  fit_one,
  future.packages = c("ranger"),
  future.seed = TRUE
))

# Summarize
pids <- vapply(res_list, function(x) as.integer(x$pid), integer(1))
elaps <- vapply(res_list, function(x) as.numeric(x$elapsed), numeric(1))
cat(sprintf("[TEST] unique PIDs: %s\n", paste(unique(pids), collapse = ", ")))
cat(sprintf("[TEST] mean elapsed per job: %.2fs (min=%.2f, max=%.2f)\n",
            mean(elaps), min(elaps), max(elaps)))

# Save results for inspection
dir.create("logs", showWarnings = FALSE, recursive = TRUE)
out_csv <- file.path("logs", "furrr_fit_test_results.csv")
utils::write.csv(data.frame(k = seq_along(pids), pid = pids, elapsed = elaps), out_csv, row.names = FALSE)
cat(sprintf("[TEST] Saved results to %s\n", out_csv))

cat("\n[TEST] Completed 04_furrr_fit_test.R\n")


