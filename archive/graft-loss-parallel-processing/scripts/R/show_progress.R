# Show Progress Utility - EC2 Compatible
# Simple progress tracking without old path references

show_progress <- function(message, ...) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("[%s] %s\n", timestamp, message))
  flush.console()
}

log_progress <- function(message, log_file = NULL, ...) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  formatted_message <- sprintf("[%s] %s\n", timestamp, message)
  
  cat(formatted_message)
  flush.console()
  
  if (!is.null(log_file)) {
    tryCatch({
      write(formatted_message, file = log_file, append = TRUE)
    }, error = function(e) {
      warning("Could not write to log file: ", e$message)
    })
  }
}
