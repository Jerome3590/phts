##' Process and Core Utilization Monitoring
##' 
##' Comprehensive monitoring of process CPU usage, core assignments, and threading
##' Designed to detect threading conflicts on high-core EC2 instances
##' 
##' Key features:
##' - Real-time CPU utilization per process
##' - Core affinity and assignment tracking  
##' - Threading conflict detection
##' - Memory usage monitoring
##' - Integration with pipeline logging

##' Get detailed process information for current R session and children
##' 
##' @param include_children Whether to include child processes
##' @param include_system Whether to include system-level info
##' @return List with process information
get_process_info <- function(include_children = TRUE, include_system = TRUE) {
  pid <- Sys.getpid()
  
  # Basic process info
  process_info <- list(
    pid = pid,
    timestamp = Sys.time(),
    cores_available = parallel::detectCores(logical = TRUE),
    cores_physical = parallel::detectCores(logical = FALSE)
  )
  
  # Get CPU usage and core assignment (Linux/Unix)
  if (.Platform$OS.type == "unix") {
    # Get detailed process info from /proc
    tryCatch({
      # CPU usage from ps
      ps_cmd <- sprintf("ps -p %d -o pid,ppid,%%cpu,%%mem,nlwp,psr,comm --no-headers", pid)
      ps_output <- suppressWarnings(system(ps_cmd, intern = TRUE))
      
      if (length(ps_output) > 0) {
        ps_fields <- strsplit(trimws(ps_output), "\\s+")[[1]]
        if (length(ps_fields) >= 7) {
          process_info$cpu_percent <- as.numeric(ps_fields[3])
          process_info$memory_percent <- as.numeric(ps_fields[4])
          process_info$threads <- as.numeric(ps_fields[5])
          process_info$current_cpu <- as.numeric(ps_fields[6])
          process_info$command <- ps_fields[7]
        }
      }
      
      # Core affinity from taskset
      taskset_cmd <- sprintf("taskset -cp %d 2>/dev/null", pid)
      taskset_output <- suppressWarnings(system(taskset_cmd, intern = TRUE))
      if (length(taskset_output) > 0) {
        # Extract CPU list from "pid 1234's current affinity list: 0-31"
        affinity_match <- regexpr(":\\s*([0-9,-]+)", taskset_output)
        if (affinity_match > 0) {
          affinity_str <- regmatches(taskset_output, affinity_match)
          affinity_str <- gsub(":\\s*", "", affinity_str)
          process_info$cpu_affinity <- affinity_str
        }
      }
      
      # Thread details from /proc/pid/task/
      task_dir <- sprintf("/proc/%d/task", pid)
      if (dir.exists(task_dir)) {
        task_dirs <- list.dirs(task_dir, recursive = FALSE)
        process_info$thread_count <- length(task_dirs)
        
        # Get CPU usage per thread (sample a few)
        thread_info <- list()
        for (i in seq_len(min(5, length(task_dirs)))) {
          tid <- basename(task_dirs[i])
          stat_file <- file.path(task_dirs[i], "stat")
          if (file.exists(stat_file)) {
            tryCatch({
              stat_content <- readLines(stat_file, n = 1)
              stat_fields <- strsplit(stat_content, " ")[[1]]
              if (length(stat_fields) >= 39) {
                thread_info[[tid]] <- list(
                  tid = tid,
                  cpu_time = as.numeric(stat_fields[14]) + as.numeric(stat_fields[15]),
                  processor = as.numeric(stat_fields[39])
                )
              }
            }, error = function(e) NULL)
          }
        }
        process_info$thread_details <- thread_info
      }
      
    }, error = function(e) {
      process_info$error <- paste("Unix process info failed:", e$message)
    })
  }
  
  # Windows process info
  if (.Platform$OS.type == "windows") {
    tryCatch({
      # Use wmic for Windows process info
      wmic_cmd <- sprintf('wmic process where "ProcessId=%d" get ProcessId,PageFileUsage,WorkingSetSize,ThreadCount,PageFaults /format:csv', pid)
      wmic_output <- suppressWarnings(system(wmic_cmd, intern = TRUE))
      
      if (length(wmic_output) > 2) {
        # Parse CSV output (skip header rows)
        csv_line <- wmic_output[length(wmic_output)]
        fields <- strsplit(csv_line, ",")[[1]]
        if (length(fields) >= 5) {
          process_info$memory_kb <- as.numeric(fields[2])
          process_info$page_faults <- as.numeric(fields[3])
          process_info$threads <- as.numeric(fields[5])
          process_info$working_set_kb <- as.numeric(fields[6])
        }
      }
    }, error = function(e) {
      process_info$error <- paste("Windows process info failed:", e$message)
    })
  }
  
  # Get child processes if requested
  if (include_children) {
    tryCatch({
      if (.Platform$OS.type == "unix") {
        # Find child processes
        pgrep_cmd <- sprintf("pgrep -P %d", pid)
        children <- suppressWarnings(system(pgrep_cmd, intern = TRUE))
        
        if (length(children) > 0) {
          child_info <- list()
          for (child_pid in children) {
            ps_cmd <- sprintf("ps -p %s -o pid,%%cpu,%%mem,nlwp,psr,comm --no-headers", child_pid)
            child_output <- suppressWarnings(system(ps_cmd, intern = TRUE))
            
            if (length(child_output) > 0) {
              child_fields <- strsplit(trimws(child_output), "\\s+")[[1]]
              if (length(child_fields) >= 6) {
                child_info[[child_pid]] <- list(
                  pid = as.numeric(child_fields[1]),
                  cpu_percent = as.numeric(child_fields[2]),
                  memory_percent = as.numeric(child_fields[3]),
                  threads = as.numeric(child_fields[4]),
                  current_cpu = as.numeric(child_fields[5]),
                  command = child_fields[6]
                )
              }
            }
          }
          process_info$children <- child_info
        }
      }
    }, error = function(e) {
      process_info$children_error <- paste("Child process info failed:", e$message)
    })
  }
  
  # System-level info if requested
  if (include_system) {
    tryCatch({
      if (.Platform$OS.type == "unix") {
        # Overall CPU usage
        uptime_output <- suppressWarnings(system("uptime", intern = TRUE))
        if (length(uptime_output) > 0) {
          # Extract load averages
          load_match <- regexpr("load average[s]*:\\s*([0-9.]+),\\s*([0-9.]+),\\s*([0-9.]+)", uptime_output)
          if (load_match > 0) {
            load_str <- regmatches(uptime_output, load_match)
            load_nums <- regmatches(load_str, gregexpr("[0-9.]+", load_str))[[1]]
            if (length(load_nums) >= 3) {
              process_info$system_load <- list(
                load_1min = as.numeric(load_nums[1]),
                load_5min = as.numeric(load_nums[2]),
                load_15min = as.numeric(load_nums[3])
              )
            }
          }
        }
        
        # Memory info
        meminfo_file <- "/proc/meminfo"
        if (file.exists(meminfo_file)) {
          meminfo <- readLines(meminfo_file, n = 10)
          mem_total <- grep("MemTotal:", meminfo, value = TRUE)
          mem_available <- grep("MemAvailable:", meminfo, value = TRUE)
          
          if (length(mem_total) > 0) {
            total_kb <- as.numeric(gsub(".*?([0-9]+).*", "\\1", mem_total))
            process_info$system_memory_total_gb <- round(total_kb / 1024 / 1024, 2)
          }
          
          if (length(mem_available) > 0) {
            available_kb <- as.numeric(gsub(".*?([0-9]+).*", "\\1", mem_available))
            process_info$system_memory_available_gb <- round(available_kb / 1024 / 1024, 2)
          }
        }
      }
    }, error = function(e) {
      process_info$system_error <- paste("System info failed:", e$message)
    })
  }
  
  return(process_info)
}

##' Log process information to file
##' 
##' @param log_file Path to log file
##' @param prefix Log message prefix
##' @param include_children Whether to include child processes
##' @param include_system Whether to include system info
log_process_info <- function(log_file, prefix = "[PROCESS]", include_children = TRUE, include_system = TRUE) {
  info <- get_process_info(include_children, include_system)
  
  # Format the log message
  log_msg <- sprintf("%s %s PID=%d Cores=%d/%d", 
                     prefix, 
                     format(info$timestamp, "%Y-%m-%d %H:%M:%S"),
                     info$pid,
                     info$cores_physical,
                     info$cores_available)
  
  # Add CPU and memory info if available
  if (!is.null(info$cpu_percent)) {
    log_msg <- paste0(log_msg, sprintf(" CPU=%.1f%% MEM=%.1f%% Threads=%d CurrentCore=%d",
                                      info$cpu_percent, info$memory_percent, 
                                      info$threads, info$current_cpu))
  }
  
  # Add CPU affinity if available
  if (!is.null(info$cpu_affinity)) {
    log_msg <- paste0(log_msg, sprintf(" Affinity=%s", info$cpu_affinity))
  }
  
  # Add system load if available
  if (!is.null(info$system_load)) {
    log_msg <- paste0(log_msg, sprintf(" Load=%.2f,%.2f,%.2f",
                                      info$system_load$load_1min,
                                      info$system_load$load_5min,
                                      info$system_load$load_15min))
  }
  
  # Add memory info if available
  if (!is.null(info$system_memory_total_gb)) {
    available_gb <- if (!is.null(info$system_memory_available_gb)) info$system_memory_available_gb else 0
    log_msg <- paste0(log_msg, sprintf(" SysMem=%.1fGB/%.1fGB", 
                                      available_gb, info$system_memory_total_gb))
  }
  
  # Write to log file
  tryCatch({
    cat(log_msg, "\n", file = log_file, append = TRUE)
    
    # Log child processes if any
    if (!is.null(info$children) && length(info$children) > 0) {
      for (child_pid in names(info$children)) {
        child <- info$children[[child_pid]]
        child_msg <- sprintf("%s   Child PID=%d CPU=%.1f%% MEM=%.1f%% Threads=%d Core=%d Cmd=%s",
                            prefix, child$pid, child$cpu_percent, child$memory_percent,
                            child$threads, child$current_cpu, child$command)
        cat(child_msg, "\n", file = log_file, append = TRUE)
      }
    }
    
    # Log thread details if available
    if (!is.null(info$thread_details) && length(info$thread_details) > 0) {
      for (tid in names(info$thread_details)) {
        thread <- info$thread_details[[tid]]
        thread_msg <- sprintf("%s   Thread TID=%s CPUTime=%d Processor=%d",
                             prefix, thread$tid, thread$cpu_time, thread$processor)
        cat(thread_msg, "\n", file = log_file, append = TRUE)
      }
    }
    
  }, error = function(e) {
    warning(sprintf("Failed to write process info to log: %s", e$message))
  })
  
  return(info)
}

##' Monitor process continuously in background
##' 
##' @param log_file Path to log file
##' @param interval_seconds Monitoring interval in seconds
##' @param duration_minutes How long to monitor (0 = indefinite)
##' @param prefix Log message prefix
##' @return Process ID of monitoring process (for stopping)
start_process_monitor <- function(log_file, interval_seconds = 30, duration_minutes = 0, prefix = "[MONITOR]") {
  # Create monitoring script
  monitor_script <- tempfile(fileext = ".R")
  
  script_content <- sprintf('
# Process monitoring script
log_file <- "%s"
interval_seconds <- %d
duration_minutes <- %d
prefix <- "%s"

# Source the process monitor functions
source("%s")

start_time <- Sys.time()
cat(sprintf("%%s %%s Starting process monitor (interval=%%ds, duration=%%dm)\\n", 
            prefix, format(start_time, "%%Y-%%m-%%d %%H:%%M:%%S"), 
            interval_seconds, duration_minutes), 
    file = log_file, append = TRUE)

while (TRUE) {
  # Log process info
  log_process_info(log_file, prefix, include_children = TRUE, include_system = TRUE)
  
  # Check if we should stop
  if (duration_minutes > 0) {
    elapsed_minutes <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
    if (elapsed_minutes >= duration_minutes) {
      cat(sprintf("%%s %%s Monitor stopping after %%d minutes\\n", 
                  prefix, format(Sys.time(), "%%Y-%%m-%%d %%H:%%M:%%S"), 
                  duration_minutes), 
          file = log_file, append = TRUE)
      break
    }
  }
  
  # Sleep
  Sys.sleep(interval_seconds)
}
', log_file, interval_seconds, duration_minutes, prefix, 
   file.path(getwd(), "scripts/R/utils/process_monitor.R"))
  
  writeLines(script_content, monitor_script)
  
  # Start monitoring in background
  if (.Platform$OS.type == "unix") {
    cmd <- sprintf("nohup Rscript %s > /dev/null 2>&1 &", monitor_script)
    system(cmd)
    
    # Get the PID of the background process
    Sys.sleep(1)  # Give it time to start
    pgrep_cmd <- sprintf("pgrep -f %s", basename(monitor_script))
    monitor_pid <- suppressWarnings(system(pgrep_cmd, intern = TRUE))
    
    if (length(monitor_pid) > 0) {
      return(as.numeric(monitor_pid[1]))
    }
  } else {
    # Windows - use start command
    cmd <- sprintf('start /B Rscript "%s"', monitor_script)
    system(cmd, wait = FALSE)
    warning("Background monitoring started on Windows - PID not available")
    return(NULL)
  }
  
  return(NULL)
}

##' Stop background process monitor
##' 
##' @param monitor_pid PID returned from start_process_monitor
stop_process_monitor <- function(monitor_pid) {
  if (is.null(monitor_pid)) {
    warning("No monitor PID provided")
    return(FALSE)
  }
  
  if (.Platform$OS.type == "unix") {
    result <- suppressWarnings(system(sprintf("kill %d", monitor_pid)))
    return(result == 0)
  } else {
    warning("Stop monitor not implemented for Windows")
    return(FALSE)
  }
}

##' Get threading conflict indicators
##' 
##' @param process_info Process info from get_process_info()
##' @return List with conflict indicators
detect_threading_conflicts <- function(process_info = NULL) {
  if (is.null(process_info)) {
    process_info <- get_process_info(include_children = TRUE, include_system = TRUE)
  }
  
  conflicts <- list(
    timestamp = Sys.time(),
    has_conflicts = FALSE,
    indicators = character(0)
  )
  
  # Check for high CPU usage with many threads
  if (!is.null(process_info$cpu_percent) && !is.null(process_info$threads)) {
    if (process_info$cpu_percent > 90 && process_info$threads > 20) {
      conflicts$has_conflicts <- TRUE
      conflicts$indicators <- c(conflicts$indicators, 
                               sprintf("High CPU (%.1f%%) with many threads (%d)", 
                                      process_info$cpu_percent, process_info$threads))
    }
  }
  
  # Check system load vs available cores
  if (!is.null(process_info$system_load) && !is.null(process_info$cores_available)) {
    load_ratio <- process_info$system_load$load_1min / process_info$cores_available
    if (load_ratio > 1.5) {
      conflicts$has_conflicts <- TRUE
      conflicts$indicators <- c(conflicts$indicators,
                               sprintf("High load ratio (%.2f) - load %.2f on %d cores",
                                      load_ratio, process_info$system_load$load_1min, 
                                      process_info$cores_available))
    }
  }
  
  # Check for many child processes with high CPU
  if (!is.null(process_info$children)) {
    high_cpu_children <- 0
    total_child_cpu <- 0
    
    for (child in process_info$children) {
      if (!is.null(child$cpu_percent)) {
        total_child_cpu <- total_child_cpu + child$cpu_percent
        if (child$cpu_percent > 50) {
          high_cpu_children <- high_cpu_children + 1
        }
      }
    }
    
    if (high_cpu_children > 2) {
      conflicts$has_conflicts <- TRUE
      conflicts$indicators <- c(conflicts$indicators,
                               sprintf("%d child processes with >50%% CPU", high_cpu_children))
    }
    
    if (total_child_cpu > process_info$cores_available * 80) {
      conflicts$has_conflicts <- TRUE
      conflicts$indicators <- c(conflicts$indicators,
                               sprintf("Total child CPU usage (%.1f%%) exceeds safe threshold", 
                                      total_child_cpu))
    }
  }
  
  return(conflicts)
}
