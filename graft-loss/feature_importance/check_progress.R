#!/usr/bin/env Rscript

# Quick progress check script
# Run this from the terminal to see what's happening

cat("\n=== MC-CV Progress Check ===\n")
cat("Time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Check output directory
output_dir <- "graft-loss/feature_importance/outputs"

# Look for new MC-CV files (with "_mc_cv" suffix)
mc_cv_files <- list.files(output_dir, pattern = ".*mc_cv.*\\.csv$", full.names = TRUE)

if (length(mc_cv_files) == 0) {
  cat("❌ No MC-CV output files found yet\n")
  cat("This means the first method-period combo hasn't finished\n\n")
} else {
  cat("✓ Found", length(mc_cv_files), "MC-CV output files:\n")
  for (f in mc_cv_files) {
    info <- file.info(f)
    cat(sprintf("  - %s (%.1f KB, modified: %s)\n", 
                basename(f), 
                info$size / 1024,
                format(info$mtime, "%H:%M:%S")))
  }
}

# Check for method-specific files (should be created as each method finishes)
method_files <- list.files(output_dir, pattern = "(original|full|full_no_covid)_(rsf|aorsf|catboost)_top20\\.csv$", 
                           full.names = TRUE)

if (length(method_files) > 0) {
  # Filter to recent files (modified in last 4 hours)
  recent_files <- method_files[file.info(method_files)$mtime > (Sys.time() - 4*3600)]
  
  if (length(recent_files) > 0) {
    cat("\n✓ Recently created files (last 4 hours):\n")
    for (f in recent_files) {
      info <- file.info(f)
      cat(sprintf("  - %s (modified: %s)\n", 
                  basename(f), 
                  format(info$mtime, "%H:%M:%S")))
    }
  } else {
    cat("\n⚠️  Method files exist but are OLD (>4 hours)\n")
  }
}

cat("\n=== Recommendation ===\n")
cat("If no files after 3+ hours, the job is likely stuck.\n")
cat("Consider interrupting and restarting with better logging.\n\n")

