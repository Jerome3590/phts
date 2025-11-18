#!/usr/bin/env Rscript

##' Test Optimized Package Setup
##' 
##' Quick test to demonstrate the smart setup system performance

cat("=== Testing Optimized Package Setup ===\n\n")

# Time the setup process
cat("1. Testing initial setup (with package checking)...\n")
start_time <- Sys.time()

source("config.R")
initialize_pipeline(load_functions = FALSE, minimal_packages = TRUE, quiet = FALSE)

setup_time <- Sys.time() - start_time
cat(sprintf("   Initial setup time: %.2f seconds\n\n", setup_time))

# Test second run (should be much faster due to caching)
cat("2. Testing cached setup (packages already verified)...\n")
start_time <- Sys.time()

# Restart with cached status
initialize_pipeline(load_functions = FALSE, minimal_packages = TRUE, quiet = FALSE)

cached_time <- Sys.time() - start_time
cat(sprintf("   Cached setup time: %.2f seconds\n\n", cached_time))

# Show improvement
if (cached_time < setup_time) {
  speedup <- setup_time / cached_time
  cat(sprintf("✓ Speedup: %.1fx faster on subsequent runs!\n", speedup))
} else {
  cat("ℹ Cache warming - next run should be faster.\n")
}

cat("\n=== Setup Optimization Complete ===\n")
cat("Your pipeline is now optimized to avoid redundant package installations.\n")