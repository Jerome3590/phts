# Resource Monitor - EC2 Compatible
# Simple resource monitoring without old path references

monitor_resources <- function() {
  # Get basic system info
  mem_info <- tryCatch({
    if (.Platform$OS.type == "unix") {
      system("free -h", intern = TRUE)
    } else {
      "Memory info not available on Windows"
    }
  }, error = function(e) "Memory info not available")
  
  cpu_info <- tryCatch({
    if (.Platform$OS.type == "unix") {
      system("nproc", intern = TRUE)
    } else {
      "CPU info not available on Windows"
    }
  }, error = function(e) "CPU info not available")
  
  list(
    memory = mem_info,
    cpu_cores = cpu_info,
    r_version = R.version.string,
    platform = .Platform$OS.type
  )
}

log_resources <- function(log_file = NULL) {
  resources <- monitor_resources()
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  message <- sprintf("[%s] Resource Monitor:\n", timestamp)
  message <- paste0(message, "  R Version: ", resources$r_version, "\n")
  message <- paste0(message, "  Platform: ", resources$platform, "\n")
  message <- paste0(message, "  CPU Cores: ", paste(resources$cpu_cores, collapse = ", "), "\n")
  message <- paste0(message, "  Memory: ", paste(resources$memory, collapse = "; "), "\n")
  
  cat(message)
  flush.console()
  
  if (!is.null(log_file)) {
    tryCatch({
      write(message, file = log_file, append = TRUE)
    }, error = function(e) {
      warning("Could not write to log file: ", e$message)
    })
  }
}
