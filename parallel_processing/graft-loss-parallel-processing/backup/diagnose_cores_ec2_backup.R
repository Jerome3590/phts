#!/usr/bin/env Rscript

##' AWS EC2 Core Detection Diagnostic
##' 
##' This script tests various methods of core detection on AWS Linux 2023

cat("=== AWS EC2 Core Detection Diagnostic ===\n")
cat("Date:", format(Sys.time()), "\n")
cat("System:", Sys.info()["sysname"], Sys.info()["release"], "\n\n")

# Method 1: R parallel::detectCores()
cat("1. R parallel::detectCores()\n")
r_logical <- parallel::detectCores(logical = TRUE)
r_physical <- parallel::detectCores(logical = FALSE)
cat(sprintf("   Logical cores: %s\n", if(is.na(r_logical)) "FAILED" else r_logical))
cat(sprintf("   Physical cores: %s\n", if(is.na(r_physical)) "FAILED" else r_physical))

# Method 2: nproc command
cat("\n2. nproc command\n")
nproc_result <- tryCatch({
  system("nproc", intern = TRUE)
}, error = function(e) paste("ERROR:", e$message))
cat(sprintf("   nproc: %s\n", nproc_result))

# Method 3: /proc/cpuinfo
cat("\n3. /proc/cpuinfo analysis\n")
if (file.exists("/proc/cpuinfo")) {
  cpuinfo_count <- tryCatch({
    system("grep -c ^processor /proc/cpuinfo", intern = TRUE)
  }, error = function(e) paste("ERROR:", e$message))
  cat(sprintf("   Processors: %s\n", cpuinfo_count))
  
  # Get CPU model
  cpu_model <- tryCatch({
    system("grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs", intern = TRUE)
  }, error = function(e) "Unknown")
  cat(sprintf("   CPU Model: %s\n", cpu_model))
} else {
  cat("   /proc/cpuinfo not available\n")
}

# Method 4: getconf
cat("\n4. getconf command\n")
getconf_result <- tryCatch({
  system("getconf _NPROCESSORS_ONLN", intern = TRUE)
}, error = function(e) paste("ERROR:", e$message))
cat(sprintf("   getconf _NPROCESSORS_ONLN: %s\n", getconf_result))

# Method 5: Environment variables
cat("\n5. Environment variables\n")
cat(sprintf("   NUMBER_OF_PROCESSORS: %s\n", Sys.getenv("NUMBER_OF_PROCESSORS", "not set")))
cat(sprintf("   NSLOTS: %s\n", Sys.getenv("NSLOTS", "not set")))

# Method 6: EC2 Instance metadata (if available)
cat("\n6. EC2 Instance metadata\n")
instance_type <- tryCatch({
  # Try to get EC2 instance type
  system("curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo 'not available'", intern = TRUE)
}, error = function(e) "not available")
cat(sprintf("   Instance type: %s\n", instance_type))

# Summary and recommendations
cat("\n=== Summary ===\n")
methods <- c(r_logical, nproc_result, cpuinfo_count, getconf_result)
valid_counts <- methods[!is.na(as.numeric(methods)) & as.numeric(methods) > 0]

if (length(valid_counts) > 0) {
  max_cores <- max(as.numeric(valid_counts))
  workers_80 <- floor(max_cores * 0.8)
  cat(sprintf("Best core count detected: %d\n", max_cores))
  cat(sprintf("Recommended workers (80%%): %d\n", workers_80))
  
  if (max_cores == 1) {
    cat("⚠️  WARNING: Only 1 core detected - this suggests a detection issue!\n")
    cat("   For EC2 instances, this is likely incorrect.\n")
  } else {
    cat("✓ Core detection appears to be working correctly.\n")
  }
} else {
  cat("❌ All core detection methods failed!\n")
}

cat("\nDiagnostic complete.\n")