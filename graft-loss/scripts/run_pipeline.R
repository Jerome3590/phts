#!/usr/bin/env Rscript

# Robust pipeline runner for the graft-loss project
# - Executes scripts/00_setup.R through scripts/05_generate_outputs.R
# - Captures warnings and errors per step
# - Logs to logs/pipeline_<timestamp>.log (stdout + messages)
# - Writes a CSV summary to logs/pipeline_<timestamp>_summary.csv

quietly <- function(expr) {
  suppressWarnings(suppressMessages(force(expr)))
}

# Derive script directory and set working directory to project root
get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) {
    normalizePath(sub("^--file=", "", file_arg)) |> dirname()
  } else if (!interactive()) {
    # Fallback: current working directory if not available
    getwd()
  } else {
    getwd()
  }
}

script_dir <- get_script_dir()
project_root <- normalizePath(file.path(script_dir, ".."))
setwd(project_root)

# Prepare logging
if (!dir.exists("logs")) dir.create("logs", recursive = TRUE, showWarnings = FALSE)
run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
log_file <- file.path("logs", sprintf("pipeline_%s.log", run_id))
summary_csv <- file.path("logs", sprintf("pipeline_%s_summary.csv", run_id))

# Open sinks to log file while also printing to console
orig_sinks_out <- sink.number(type = "output")
orig_sinks_msg <- sink.number(type = "message")

# Create a message connection because sink(type="message") requires a connection
msg_con <- file(log_file, open = "a")

# Ensure sinks and connections are restored/closed on exit
.on_exit <- local({
  out_n <- orig_sinks_out
  msg_n <- orig_sinks_msg
  msg_conn <- msg_con
  function() {
    while (sink.number() > out_n) sink()
    while (sink.number(type = "message") > msg_n) sink(type = "message")
    if (isOpen(msg_conn)) close(msg_conn)
  }
})

on.exit(.on_exit(), add = TRUE)

sink(log_file, append = TRUE, split = TRUE)
sink(msg_con, type = "message")

cat("==== Graft Loss Pipeline Run ====\n")
cat(sprintf("Run ID       : %s\n", run_id))
cat(sprintf("Project Root : %s\n", project_root))
cat(sprintf("R Version    : %s\n", paste(R.version$major, R.version$minor, sep = ".")))
cat(sprintf("Timestamp    : %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")))
cat(sprintf("EXCLUDE_COVID: %s\n", Sys.getenv("EXCLUDE_COVID", "0")))
cat(sprintf("ORIGINAL_STUDY: %s\n", Sys.getenv("ORIGINAL_STUDY", "0")))
cat(sprintf("USE_ENCODED : %s\n", Sys.getenv("USE_ENCODED", "0")))
cat(sprintf("MC_CV       : %s\n", Sys.getenv("MC_CV", "0")))
cat(sprintf("MC_START_AT : %s\n", Sys.getenv("MC_START_AT", "1")))
cat(sprintf("MC_MAX_SPLITS: %s\n", Sys.getenv("MC_MAX_SPLITS", "")))
cat("=================================\n\n")

# Steps to run
steps <- c(
  "00_setup.R",
  "01_prepare_data.R",
  "02_resampling.R",
  "03_prep_model_data.R",
  "04_fit_model.R",
  "05_generate_outputs.R"
)

# Support partial execution via environment variables:
#   START_AT = step base name (e.g., '03_prep_model_data' or '03') to begin from that step (inclusive)
#   STOP_AT  = step base name to stop after completing that step
start_at <- Sys.getenv('START_AT', '')
stop_at  <- Sys.getenv('STOP_AT', '')

normalize_step_key <- function(x){
  x <- trimws(tolower(x))
  x <- sub('\n$', '', x)
  if(x == '') return('')
  # Allow just numeric prefix (e.g., '03')
  if(grepl('^[0-9]{2}$', x)){
    matched <- grep(paste0('^', x, '_'), sub('\\.R$','', steps), value = TRUE)
    if(length(matched)) return(matched[1]) else return('')
  }
  # Strip .R if present
  x <- sub('\\.r$', '', x)
  x
}

start_at <- normalize_step_key(start_at)
stop_at  <- normalize_step_key(stop_at)

if(nzchar(start_at) && !(start_at %in% sub('\\.R$','', steps))){
  warning(sprintf('START_AT="%s" not recognized; ignoring.', start_at))
  start_at <- ''
}
if(nzchar(stop_at) && !(stop_at %in% sub('\\.R$','', steps))){
  warning(sprintf('STOP_AT="%s" not recognized; ignoring.', stop_at))
  stop_at <- ''
}

start_index <- if(nzchar(start_at)) match(start_at, sub('\\.R$','', steps)) else 1L
stop_index  <- if(nzchar(stop_at))  match(stop_at,  sub('\\.R$','', steps)) else length(steps)

if(start_index > 1L){
  cat(sprintf('Partial execution: starting at step %s (index %d)\n', start_at, start_index))
}
if(stop_index < length(steps)){
  cat(sprintf('Partial execution: will stop after step %s (index %d)\n', stop_at, stop_index))
}

results <- list()

for (i in seq_along(steps)) {
  if(i < start_index) next
  if(i > stop_index) break
  step <- steps[i]
  step_path <- file.path("scripts", step)
  step_name <- sub("\\.R$", "", step)
  # Progress JSON helper
  progress_dir <- file.path('data','progress')
  if (!dir.exists(progress_dir)) dir.create(progress_dir, recursive = TRUE, showWarnings = FALSE)
  progress_file <- file.path(progress_dir, 'pipeline_progress.json')
  write_progress_step <- function(current_step, status = 'running', note = NULL) {
    idx <- match(current_step, sub("\\.R$", "", steps))
    obj <- list(
      timestamp = format(Sys.time(), '%Y-%m-%dT%H:%M:%S%z'),
      current_step = current_step,
      step_index = idx,
      total_steps = length(steps),
      step_names = sub('\\.R$','', steps),
      status = status,
      note = note
    )
    tmp <- paste0(progress_file, '.tmp')
    jsonlite::write_json(obj, tmp, auto_unbox = TRUE, pretty = TRUE)
    file.rename(tmp, progress_file)
  }

  if (!file.exists(step_path)) {
    msg <- sprintf("Missing script: %s", step_path)
    cat(sprintf("[STEP MISSING] %s | %s\n", step_name, msg))
    results[[length(results) + 1]] <- data.frame(
      step = step_name,
      status = "missing",
      start_time = NA_character_,
      end_time = NA_character_,
      duration_sec = NA_real_,
      warnings = 0L,
      error_message = msg,
      stringsAsFactors = FALSE
    )
    next
  }

  start_time <- Sys.time()
  cat(sprintf("[STEP START ] %s | %s\n", step_name, format(start_time, "%Y-%m-%d %H:%M:%S")))
  write_progress_step(step_name, status = 'running')

  warnings_vec <- character(0)
  err_msg <- NULL

  ok <- tryCatch(
    withCallingHandlers({
      # Use a new local environment for the script to avoid clobbering global vars
      local_env <- new.env(parent = globalenv())
      source(step_path, local = local_env, echo = TRUE, chdir = FALSE, print.eval = FALSE)
    }, warning = function(w) {
      wmsg <- conditionMessage(w)
      warnings_vec <<- c(warnings_vec, wmsg)
      message(sprintf("[WARNING %s] %s", step_name, wmsg))
      invokeRestart("muffleWarning")
    }),
    error = function(e) {
      err_msg <<- conditionMessage(e)
      message(sprintf("[ERROR   %s] %s", step_name, err_msg))
      FALSE
    }
  )

  end_time <- Sys.time()
  duration <- as.numeric(difftime(end_time, start_time, units = "secs"))

  status <- if (!is.null(err_msg)) "error" else if (length(warnings_vec) > 0) "warning" else "ok"

  cat(sprintf(
    "[STEP END   ] %s | status=%s | duration=%.1fs | warnings=%d\n\n",
    step_name, status, duration, length(warnings_vec)
  ))
  write_progress_step(step_name, status = status)

  results[[length(results) + 1]] <- data.frame(
    step = step_name,
    status = status,
    start_time = format(start_time, "%Y-%m-%d %H:%M:%S"),
    end_time = format(end_time, "%Y-%m-%d %H:%M:%S"),
    duration_sec = duration,
    warnings = length(warnings_vec),
    error_message = if (is.null(err_msg)) "" else err_msg,
    stringsAsFactors = FALSE
  )
}

# Bind results and write summary CSV
summary_df <- do.call(rbind, results)
utils::write.csv(summary_df, summary_csv, row.names = FALSE)

cat("=================================\n")
cat(sprintf("Log file     : %s\n", log_file))
cat(sprintf("Summary CSV  : %s\n", summary_csv))
cat("=================================\n\n")

# Also print a compact summary to console/log
print(summary_df)

# Exit code: 0 if all ok/warning/missing, 1 if any error
if (any(summary_df$status == "error", na.rm = TRUE)) {
  quit(status = 1L)
} else {
  quit(status = 0L)
}
