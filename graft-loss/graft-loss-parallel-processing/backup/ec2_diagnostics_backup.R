#!/usr/bin/env Rscript

# EC2 File Load Error Diagnostics & Fix
# Run this first on EC2 to diagnose and fix file loading issues

cat("🔧 EC2 File Load Diagnostics\n")
cat("============================\n")

# Check critical directories
required_dirs <- c("R", "R/utils", "scripts", "logs", "data")
missing_dirs <- c()

for (dir in required_dirs) {
  if (!dir.exists(dir)) {
    missing_dirs <- c(missing_dirs, dir)
    cat(sprintf("❌ Missing directory: %s\n", dir))
  } else {
    cat(sprintf("✅ Found directory: %s\n", dir))
  }
}

# Create missing directories
if (length(missing_dirs) > 0) {
  cat("\n🛠️  Creating missing directories...\n")
  for (dir in missing_dirs) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    cat(sprintf("✅ Created: %s\n", dir))
  }
}

# Check critical files
required_files <- c(
  "R/utils/parallel_utils.R",
  "scripts/run_pipeline.R", 
  "scripts/enhanced_pipeline_logger_v2.R",
  "scripts/packages.R"
)

missing_files <- c()
for (file in required_files) {
  if (!file.exists(file)) {
    missing_files <- c(missing_files, file)
    cat(sprintf("❌ Missing file: %s\n", file))
  } else {
    cat(sprintf("✅ Found file: %s\n", file))
  }
}

# Check R package availability
cat("\n📦 Package Availability Check\n")
cat("─────────────────────────\n")

# Core packages needed by the pipeline
core_packages <- c(
  "parallel", "foreach", "survival", "ranger", 
  "tidyverse", "tidymodels", "magrittr", "here"
)

missing_packages <- c()
for (pkg in core_packages) {
  available <- tryCatch({
    suppressMessages(library(pkg, character.only = TRUE, logical.return = TRUE))
  }, error = function(e) FALSE)
  
  if (available) {
    cat(sprintf("✅ %s\n", pkg))
  } else {
    missing_packages <- c(missing_packages, pkg)
    cat(sprintf("❌ %s (not installed)\n", pkg))
  }
}

# Check environment variables
cat("\n🌍 Environment Variables\n")
cat("─────────────────────\n")
important_vars <- c("R_MAX_VSIZE", "OMP_NUM_THREADS", "MC_WORKER_THREADS")
for (var in important_vars) {
  val <- Sys.getenv(var, unset = "NOT_SET")
  cat(sprintf("%s: %s\n", var, val))
}

# System resource check
cat("\n💻 System Resources\n")
cat("─────────────────\n")
tryCatch({
  if (file.exists("/proc/meminfo")) {
    meminfo <- readLines("/proc/meminfo")
    total_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemTotal", meminfo)])) / 1024 / 1024
    avail_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemAvailable", meminfo)])) / 1024 / 1024
    cat(sprintf("Memory: %.1f GB total, %.1f GB available\n", total_mem, avail_mem))
  }
  
  cores <- parallel::detectCores(logical = TRUE)
  cat(sprintf("CPU cores: %d\n", cores))
}, error = function(e) {
  cat("System info detection failed\n")
})

# Generate fix script if issues found
if (length(missing_files) > 0 || length(missing_packages) > 0) {
  cat("\n⚠️  ISSUES DETECTED\n")
  cat("=================\n")
  
  if (length(missing_files) > 0) {
    cat("Missing files:\n")
    for (file in missing_files) {
      cat(sprintf("  - %s\n", file))
    }
  }
  
  if (length(missing_packages) > 0) {
    cat("Missing packages:\n")
    for (pkg in missing_packages) {
      cat(sprintf("  - %s\n", pkg))
    }
    
    # Create package installation script
    cat("\n🔧 Creating package installation script...\n")
    install_script <- "#!/usr/bin/env Rscript\n\n"
    install_script <- paste0(install_script, "# Auto-generated package installer for EC2\n")
    install_script <- paste0(install_script, "cat('Installing missing packages...\\n')\n\n")
    
    for (pkg in missing_packages) {
      install_script <- paste0(install_script, sprintf("tryCatch({\n"))
      install_script <- paste0(install_script, sprintf("  install.packages('%s', repos = 'https://cloud.r-project.org')\n", pkg))
      install_script <- paste0(install_script, sprintf("  cat('✅ Installed %s\\n')\n", pkg))
      install_script <- paste0(install_script, "}, error = function(e) {\n")
      install_script <- paste0(install_script, sprintf("  cat('❌ Failed to install %s:', e$message, '\\n')\n", pkg))
      install_script <- paste0(install_script, "})\n\n")
    }
    
    writeLines(install_script, "scripts/install_missing_packages.R")
    cat("✅ Created: scripts/install_missing_packages.R\n")
    cat("Run with: Rscript scripts/install_missing_packages.R\n")
  }
  
  cat("\n❌ Fix required before running pipeline\n")
  quit(status = 1)
} else {
  cat("\n✅ ALL CHECKS PASSED\n")
  cat("==================\n")
  cat("System is ready for pipeline execution!\n")
  quit(status = 0)
}