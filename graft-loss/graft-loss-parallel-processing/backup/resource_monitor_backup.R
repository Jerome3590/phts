#!/usr/bin/env Rscript

# Comprehensive Resource Monitor for 3-Dataset Pipeline
# Provides detailed resource tracking and step analysis

cat("=== Graft Loss Pipeline: Comprehensive Resource Monitor ===\n")
cat(sprintf("Timestamp: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")))
cat("=" %strrep% 60, "\n\n")

# System Overview
cat("=== 1TB RAM EC2 System Overview ===\n")
system("echo 'Memory:' && free -h | head -n 2", intern = FALSE)
system("echo 'CPU Info:' && lscpu | grep -E '(CPU\\(s\\)|Thread|Core|Socket)' | head -n 4 2>/dev/null || echo 'CPU info not available'", intern = FALSE)
system("echo 'Load Average:' && uptime", intern = FALSE)
cat("\n")

# Active R Processes
cat("=== R Process Monitoring ===\n")
r_processes <- system("ps aux | grep -E '(Rscript|enhanced_pipeline_logger|run_pipeline)' | grep -v grep", intern = TRUE)

if (length(r_processes) > 0 && r_processes[1] != "") {
  cat("Active R Processes:\n")
  cat("PID     %CPU  %MEM    VSZ    RSS  COMMAND\n")
  for (proc in r_processes) {
    # Parse ps output: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
    fields <- strsplit(proc, "\\s+")[[1]]
    if (length(fields) >= 11) {
      pid <- fields[2]
      cpu <- fields[3]
      mem <- fields[4]
      vsz <- fields[5]
      rss <- fields[6]
      cmd <- paste(fields[11:length(fields)], collapse = " ")
      cmd_short <- if (nchar(cmd) > 50) paste0(substr(cmd, 1, 47), "...") else cmd
      cat(sprintf("%-7s %5s %5s %7s %7s  %s\n", pid, cpu, mem, vsz, rss, cmd_short))
    }
  }
  
  # Total memory used by R processes
  total_rss <- sum(as.numeric(gsub("[^0-9]", "", 
    system("ps aux | grep -E '(Rscript|enhanced_pipeline_logger)' | grep -v grep | awk '{sum+=$6} END {print sum}'", intern = TRUE)
  )), na.rm = TRUE)
  cat(sprintf("\nTotal R Memory Usage: %.1f GB\n", total_rss / 1024 / 1024))
} else {
  cat("No R processes currently running\n")
}
cat("\n")

# Dataset-specific Analysis
cat("=== Dataset Progress & Resource Analysis ===\n")
datasets <- c("original_study", "full_with_covid", "full_without_covid")

for (dataset in datasets) {
  log_file <- sprintf("logs/orch_bg_%s.log", dataset)
  
  cat(sprintf("--- %s ---\n", toupper(dataset)))
  
  if (file.exists(log_file)) {
    # Current step
    current_step <- system(sprintf("grep '\\[STEP:' %s | tail -n 1", shQuote(log_file)), intern = TRUE)
    if (length(current_step) > 0) {
      step_name <- gsub(".*\\[STEP: ([^]]+)\\].*", "\\1", current_step)
      timestamp <- gsub("^\\[([^]]+)\\].*", "\\1", current_step)
      cat(sprintf("Current Step: %s (as of %s)\n", step_name, timestamp))
    }
    
    # Progress tracking (count completed targets)
    targets_completed <- system(sprintf("grep -c 'Completed target:' %s 2>/dev/null || echo '0'", shQuote(log_file)), intern = TRUE)
    targets_started <- system(sprintf("grep -c 'Starting target:' %s 2>/dev/null || echo '0'", shQuote(log_file)), intern = TRUE)
    cat(sprintf("Targets: %s completed, %s started\n", targets_completed, targets_started))
    
    # Latest resource readings
    latest_resources <- system(sprintf("grep 'MEM:.*CPU:' %s | tail -n 3", shQuote(log_file)), intern = TRUE)
    if (length(latest_resources) > 0) {
      cat("Recent Resource Usage:\n")
      for (res in latest_resources) {
        timestamp <- gsub("^\\[([^]]+)\\].*", "\\1", res)
        mem_info <- gsub(".*\\|(.*MEM: [^|]+)\\|.*", "\\1", res)
        cpu_info <- gsub(".*\\|(.*CPU: [^|]+)\\|.*", "\\1", res)
        cat(sprintf("  %s: %s |%s\n", 
                   substr(timestamp, 12, 19), # Just time portion
                   trimws(mem_info), trimws(cpu_info)))
      }
    }
    
    # Error checking
    errors <- system(sprintf("grep -c 'ERROR' %s 2>/dev/null || echo '0'", shQuote(log_file)), intern = TRUE)
    if (as.integer(errors) > 0) {
      cat(sprintf("⚠️  Errors detected: %s\n", errors))
      recent_error <- system(sprintf("grep 'ERROR' %s | tail -n 1", shQuote(log_file)), intern = TRUE)
      if (length(recent_error) > 0) {
        cat(sprintf("   Latest: %s\n", gsub(".*ERROR.*\\|.*\\|", "", recent_error)))
      }
    }
    
    # Completion check
    completed <- system(sprintf("grep -c 'COMPLETE' %s 2>/dev/null || echo '0'", shQuote(log_file)), intern = TRUE)
    if (as.integer(completed) > 0) {
      cat("✅ Status: COMPLETED\n")
    } else {
      cat("🔄 Status: RUNNING\n")
    }
    
  } else {
    cat("Log file not found - process may not have started yet\n")
  }
  cat("\n")
}

# Resource Utilization Summary
cat("=== Resource Utilization Summary ===\n")

# Memory utilization
mem_info <- system("free | grep '^Mem:'", intern = TRUE)
if (length(mem_info) > 0) {
  mem_fields <- as.numeric(strsplit(mem_info, "\\s+")[[1]][-1])
  total_mem <- mem_fields[1] / 1024 / 1024  # GB
  used_mem <- mem_fields[2] / 1024 / 1024   # GB
  available_mem <- mem_fields[6] / 1024 / 1024  # GB (available column)
  
  mem_percent <- (used_mem / total_mem) * 100
  cat(sprintf("Memory: %.1f GB / %.1f GB (%.1f%% used, %.1f GB available)\n", 
             used_mem, total_mem, mem_percent, available_mem))
}

# CPU utilization (if available)
cpu_usage <- system("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo 'N/A'", intern = TRUE)
if (cpu_usage != "N/A") {
  cat(sprintf("CPU Usage: %s%%\n", cpu_usage))
}

# Disk usage for logs
log_size <- system("du -sh logs/ 2>/dev/null | cut -f1 || echo 'N/A'", intern = TRUE)
cat(sprintf("Log Directory Size: %s\n", log_size))

cat("\n=== Monitor Complete ===\n")
cat(sprintf("Run again with: Rscript scripts/resource_monitor.R\n"))