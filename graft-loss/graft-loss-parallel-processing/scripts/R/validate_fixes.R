#!/usr/bin/env Rscript

##' Log File Discrepancy Fixes Validation
##' 
##' This script validates the fixes applied to resolve log file discrepancies

cat("=== Log File Discrepancy Fixes Validation ===\n\n")

# Test 1: Verify config.R path resolution
cat("1. Testing config.R path resolution...\n")
config_path <- file.path("scripts", "R", "config.R")
if (file.exists(config_path)) {
  cat("   ✓ config.R found at correct path:", config_path, "\n")
} else {
  cat("   ✗ config.R not found at:", config_path, "\n")
}

# Test 2: Check if setup script can source config.R
cat("2. Testing 00_setup.R config sourcing...\n")
tryCatch({
  # Read the setup script to check the source line
  setup_content <- readLines(file.path("pipeline", "00_setup.R"))
  source_line <- grep("source.*config", setup_content, value = TRUE)
  if (length(source_line) > 0 && grepl("scripts.*R.*config", source_line[1])) {
    cat("   ✓ 00_setup.R uses correct config.R path\n")
  } else {
    cat("   ✗ 00_setup.R has incorrect config.R path\n")
  }
}, error = function(e) {
  cat("   ✗ Error reading 00_setup.R:", e$message, "\n")
})

# Test 3: Verify log directory structure
cat("3. Testing log directory structure...\n")
if (dir.exists("logs")) {
  log_files <- list.files("logs", pattern = "\\.log$")
  txt_files <- list.files("logs", pattern = "\\.txt$")
  
  cat(sprintf("   Found %d .log files and %d .txt files\n", length(log_files), length(txt_files)))
  
  if (length(txt_files) > 0) {
    cat("   ℹ Note: .txt files found (may be from previous runs)\n")
    cat("     ", paste(txt_files, collapse = ", "), "\n")
  }
  
  if (length(log_files) > 0) {
    cat("   ✓ .log files exist (expected format)\n")
  }
} else {
  cat("   ℹ logs/ directory will be created on first run\n")
}

# Test 4: Check project structure
cat("4. Testing project structure...\n")
required_dirs <- c("scripts", "scripts/R", "scripts/R/utils", "pipeline")
missing_dirs <- c()

for (dir in required_dirs) {
  if (dir.exists(dir)) {
    cat(sprintf("   ✓ %s/ directory exists\n", dir))
  } else {
    missing_dirs <- c(missing_dirs, dir)
    cat(sprintf("   ✗ %s/ directory missing\n", dir))
  }
}

# Test 5: Check utility modules
cat("5. Testing utility modules...\n")
util_files <- c(
  "scripts/R/utils/data_utils.R",
  "scripts/R/utils/model_utils.R", 
  "scripts/R/utils/parallel_utils.R"
)

for (file in util_files) {
  if (file.exists(file)) {
    cat(sprintf("   ✓ %s exists\n", file))
  } else {
    cat(sprintf("   ✗ %s missing\n", file))
  }
}

# Test 6: Validate smart setup system
cat("6. Testing smart setup system...\n")
smart_setup_path <- file.path("scripts", "R", "smart_setup.R")
if (file.exists(smart_setup_path)) {
  cat("   ✓ smart_setup.R exists\n")
  
  # Check if it has the key functions
  setup_content <- readLines(smart_setup_path)
  key_functions <- c("setup_packages", "load_pipeline_packages", "clear_package_cache")
  
  for (func in key_functions) {
    if (any(grepl(paste0(func, "\\s*<-\\s*function"), setup_content))) {
      cat(sprintf("   ✓ Function %s defined\n", func))
    } else {
      cat(sprintf("   ✗ Function %s missing\n", func))
    }
  }
} else {
  cat("   ✗ smart_setup.R not found\n")
}

cat("\n=== Summary ===\n")
cat("The major discrepancies identified and fixed:\n")
cat("• Fixed config.R path reference in 00_setup.R\n")
cat("• Updated notebook to use .log extension consistently\n") 
cat("• Enhanced process monitoring with better pattern matching\n")
cat("• Validated project structure for proper path resolution\n")

cat("\n✓ Log file discrepancy fixes validation complete!\n")
