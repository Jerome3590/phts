#!/usr/bin/env Rscript
".libPaths" # silence R CMD check note if any

suppressPackageStartupMessages({
  if (!requireNamespace('jsonlite', quietly = TRUE)) {
    stop('Package jsonlite required. Install with install.packages("jsonlite").')
  }
})

progress_file <- file.path('model_data','progress','pipeline_progress.json')
if (!file.exists(progress_file)) {
  cat('No progress file found at', progress_file, '\n')
  quit(status = 1)
}

dat <- tryCatch(jsonlite::read_json(progress_file, simplifyVector = TRUE), error = function(e) NULL)
if (is.null(dat)) {
  cat('Could not parse progress file (maybe being written). Try again.\n')
  quit(status = 2)
}

pct <- if (!is.null(dat$mc) && !is.null(dat$mc$percent)) sprintf('%5.1f%%', dat$mc$percent) else NA

cat('Timestamp :', dat$timestamp, '\n')
cat('Step      :', sprintf('%s (%d/%d)', dat$current_step, dat$step_index, dat$total_steps), '\n')
cat('Status    :', dat$status, '\n')
if (!is.na(pct)) {
  cat('MC Split  :', sprintf('%d / %d', dat$mc$split_done, dat$mc$split_total), '\n')
  cat('Progress  :', pct, '\n')
  cat('Elapsed   :', sprintf('%.1f s', dat$mc$elapsed_sec), '\n')
  if (!is.null(dat$mc$eta_sec) && is.finite(dat$mc$eta_sec)) {
    cat('ETA       :', sprintf('%.1f s', dat$mc$eta_sec), '\n')
  }
}
if (!is.null(dat$note) && nzchar(dat$note)) cat('Note      :', dat$note, '\n')
