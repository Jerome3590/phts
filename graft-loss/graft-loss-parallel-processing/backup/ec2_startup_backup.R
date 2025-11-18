#!/usr/bin/env Rscript

# EC2 Startup & Fix Script for File Load Errors
# Run this before launching the pipeline on EC2

cat("🚀 EC2 Pipeline Startup & Fix\n")
cat("==============================\n")

# Set working directory to project root
if (basename(getwd()) == "scripts") {
  setwd("..")
}

project_root <- getwd()
cat(sprintf("Project root: %s\n", project_root))

# 1. Check and create required directories
required_dirs <- c("logs", "R/utils", "data", "output")
cat("\n📁 Directory Setup\n")
cat("─────────────────\n")

for (dir in required_dirs) {
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    cat(sprintf("✅ Created: %s\n", dir))
  } else {
    cat(sprintf("✅ Exists: %s\n", dir))
  }
}

# 2. Set critical environment variables for EC2
cat("\n🌍 Environment Configuration\n")
cat("───────────────────────────\n")

# Memory settings for large EC2 instances
Sys.setenv(R_MAX_VSIZE = "950Gb")
cat("✅ R_MAX_VSIZE = 950Gb\n")

# Thread control for parallel safety
Sys.setenv(OMP_NUM_THREADS = "1")
Sys.setenv(OPENBLAS_NUM_THREADS = "1") 
Sys.setenv(MKL_NUM_THREADS = "1")
Sys.setenv(VECLIB_MAXIMUM_THREADS = "1")
cat("✅ Thread limits set for parallel safety\n")

# 3. Test critical file paths
cat("\n📋 File Dependencies Check\n")
cat("─────────────────────────\n")

critical_files <- list(
  "Main orchestrator" = "scripts/run_pipeline.R",
  "Enhanced logger v2" = "scripts/enhanced_pipeline_logger_v2.R", 
  "Parallel utilities" = "R/utils/parallel_utils.R",
  "Main pipeline" = "scripts/run_pipeline.R"
)

all_files_ok <- TRUE
for (desc in names(critical_files)) {
  file_path <- critical_files[[desc]]
  if (file.exists(file_path)) {
    # Test if file can be parsed
    parse_ok <- tryCatch({
      parse(file_path)
      TRUE
    }, error = function(e) {
      cat(sprintf("❌ %s: Parse error - %s\n", desc, e$message))
      FALSE
    })
    
    if (parse_ok) {
      cat(sprintf("✅ %s\n", desc))
    } else {
      all_files_ok <- FALSE
    }
  } else {
    cat(sprintf("❌ %s: File not found (%s)\n", desc, file_path))
    all_files_ok <- FALSE
  }
}

# 4. Test package availability (minimal required)
cat("\n📦 Core Package Check\n")
cat("────────────────────\n")

essential_packages <- c("parallel", "utils", "stats", "base")
missing_packages <- c()

for (pkg in essential_packages) {
  available <- tryCatch({
    requireNamespace(pkg, quietly = TRUE)
  }, error = function(e) FALSE)
  
  if (available) {
    cat(sprintf("✅ %s\n", pkg))
  } else {
    cat(sprintf("❌ %s\n", pkg))
    missing_packages <- c(missing_packages, pkg)
    all_files_ok <- FALSE
  }
}

# 5. System resource verification
cat("\n💻 System Resources\n") 
cat("─────────────────\n")

tryCatch({
  # Memory check
  if (file.exists("/proc/meminfo")) {
    meminfo <- readLines("/proc/meminfo")
    total_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemTotal", meminfo)])) / 1024 / 1024
    avail_mem <- as.numeric(gsub(".*: *([0-9]+) kB", "\\1", meminfo[grep("MemAvailable", meminfo)])) / 1024 / 1024
    cat(sprintf("✅ Memory: %.1f GB total, %.1f GB available\n", total_mem, avail_mem))
    
    # Warn if insufficient memory
    if (total_mem < 100) {
      cat("⚠️  WARNING: Less than 100GB RAM detected. Pipeline may fail.\n")
    }
  }
  
  # CPU check
  cores <- parallel::detectCores(logical = TRUE)
  cat(sprintf("✅ CPU cores: %d detected\n", cores))
  
}, error = function(e) {
  cat("⚠️  System resource detection failed\n")
})

# 6. Create run command for easy execution
cat("\n🎯 Pipeline Execution\n")
cat("────────────────────\n")

if (all_files_ok) {
  cat("✅ All checks passed! System ready for pipeline execution.\n\n")
  
  # Create convenient run command
  run_cmd <- "Rscript scripts/run_pipeline.R"
  cat("💡 To start the pipeline:\n")
  cat(sprintf("   %s\n\n", run_cmd))
  
  # Create launch script
  launch_script <- "#!/bin/bash\n\n"
  launch_script <- paste0(launch_script, "# Auto-generated EC2 launch script\n")
  launch_script <- paste0(launch_script, "echo 'Starting 3-dataset parallel pipeline...'\n")
  launch_script <- paste0(launch_script, sprintf("nohup %s > logs/pipeline_master.log 2>&1 &\n", run_cmd))
  launch_script <- paste0(launch_script, "echo \"Pipeline started. Monitor with: tail -f logs/pipeline_master.log\"\n")
  
  writeLines(launch_script, "launch_pipeline.sh")
  system("chmod +x launch_pipeline.sh")
  cat("✅ Created executable launch script: ./launch_pipeline.sh\n")
  
  quit(status = 0)
} else {
  cat("\n❌ ERRORS DETECTED - Pipeline not ready\n")
  cat("=====================================\n")
  
  if (length(missing_packages) > 0) {
    cat("Missing packages. Install with:\n")
    for (pkg in missing_packages) {
      cat(sprintf("  install.packages('%s')\n", pkg))
    }
  }
  
  cat("\nFix the above issues before running the pipeline.\n")
  quit(status = 1)
}