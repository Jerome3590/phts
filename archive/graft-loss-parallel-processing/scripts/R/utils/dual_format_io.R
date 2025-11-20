##' Dual-format I/O utilities for robust data persistence
##' 
##' These functions save data in both .rds and .csv formats to provide:
##' 1. Backup options when .rds files become corrupted or incompatible
##' 2. CatBoost compatibility - CatBoost requires CSV format for model training
##' 3. Cross-platform compatibility and human-readable format

##' Save data frame in both RDS and CSV formats
##' @param data Data frame to save
##' @param base_path Base file path without extension
##' @param compress Whether to compress RDS file (default: TRUE)
##' @param csv_options List of additional options for write.csv
##' @return List with paths of saved files
##' @examples
##' save_dual_format(mtcars, "data/cars")
##' # Creates: data/cars.rds and data/cars.csv
save_dual_format <- function(data, base_path, compress = TRUE, csv_options = list()) {
  if (!inherits(data, "data.frame")) {
    stop("save_dual_format only supports data.frame objects")
  }
  
  # Ensure directory exists
  dir.create(dirname(base_path), showWarnings = FALSE, recursive = TRUE)
  
  # Define file paths
  rds_path <- paste0(base_path, ".rds")
  csv_path <- paste0(base_path, ".csv")
  
  # Save RDS with error handling
  rds_success <- tryCatch({
    saveRDS(data, rds_path, compress = compress)
    TRUE
  }, error = function(e) {
    warning(sprintf("Failed to save RDS file '%s': %s", rds_path, e$message))
    FALSE
  })
  
  # Save CSV with error handling
  csv_success <- tryCatch({
    # Default CSV options
    default_options <- list(
      row.names = FALSE,
      na = ""
    )
    
    # Merge with user options
    final_options <- modifyList(default_options, csv_options)
    final_options$x <- data
    final_options$file <- csv_path
    
    do.call(write.csv, final_options)
    TRUE
  }, error = function(e) {
    warning(sprintf("Failed to save CSV file '%s': %s", csv_path, e$message))
    FALSE
  })
  
  # Return results
  result <- list(
    rds_path = if (rds_success) rds_path else NULL,
    csv_path = if (csv_success) csv_path else NULL,
    rds_success = rds_success,
    csv_success = csv_success
  )
  
  if (rds_success && csv_success) {
    message(sprintf("Saved dual format: %s (.rds + .csv)", basename(base_path)))
  } else if (rds_success) {
    warning(sprintf("Only RDS saved: %s", basename(base_path)))
  } else if (csv_success) {
    warning(sprintf("Only CSV saved: %s", basename(base_path)))
  } else {
    stop(sprintf("Failed to save in any format: %s", basename(base_path)))
  }
  
  return(result)
}

##' Load data with automatic fallback from RDS to CSV
##' @param base_path Base file path without extension
##' @param prefer_rds Whether to try RDS first (default: TRUE)
##' @param csv_options List of additional options for read.csv
##' @return Data frame
##' @examples
##' data <- load_dual_format("data/cars")
##' # Tries: data/cars.rds, then data/cars.csv
load_dual_format <- function(base_path, prefer_rds = TRUE, csv_options = list()) {
  rds_path <- paste0(base_path, ".rds")
  csv_path <- paste0(base_path, ".csv")
  
  # Define loading functions
  load_rds <- function() {
    if (!file.exists(rds_path)) {
      stop(sprintf("RDS file not found: %s", rds_path))
    }
    tryCatch({
      readRDS(rds_path)
    }, error = function(e) {
      if (grepl("unknown type|ReadItem", e$message, ignore.case = TRUE)) {
        stop(sprintf("RDS file corrupted or incompatible: %s", e$message))
      } else {
        stop(e)
      }
    })
  }
  
  load_csv <- function() {
    if (!file.exists(csv_path)) {
      stop(sprintf("CSV file not found: %s", csv_path))
    }
    
    # Default CSV options
    default_options <- list(
      stringsAsFactors = FALSE,
      na.strings = c("", "NA")
    )
    
    # Merge with user options
    final_options <- modifyList(default_options, csv_options)
    final_options$file <- csv_path
    
    do.call(read.csv, final_options)
  }
  
  # Try loading in preferred order
  if (prefer_rds) {
    # Try RDS first, fallback to CSV
    tryCatch({
      data <- load_rds()
      message(sprintf("Loaded from RDS: %s", basename(rds_path)))
      return(data)
    }, error = function(e_rds) {
      message(sprintf("RDS failed (%s), trying CSV...", e_rds$message))
      tryCatch({
        data <- load_csv()
        message(sprintf("Loaded from CSV fallback: %s", basename(csv_path)))
        return(data)
      }, error = function(e_csv) {
        stop(sprintf("Both formats failed. RDS: %s. CSV: %s", e_rds$message, e_csv$message))
      })
    })
  } else {
    # Try CSV first, fallback to RDS
    tryCatch({
      data <- load_csv()
      message(sprintf("Loaded from CSV: %s", basename(csv_path)))
      return(data)
    }, error = function(e_csv) {
      message(sprintf("CSV failed (%s), trying RDS...", e_csv$message))
      tryCatch({
        data <- load_rds()
        message(sprintf("Loaded from RDS fallback: %s", basename(rds_path)))
        return(data)
      }, error = function(e_rds) {
        stop(sprintf("Both formats failed. CSV: %s. RDS: %s", e_csv$message, e_rds$message))
      })
    })
  }
}

##' Save model object with metadata in dual format
##' @param model Model object to save
##' @param base_path Base file path without extension
##' @param metadata List of metadata to save alongside model
##' @return List with paths of saved files
save_model_dual_format <- function(model, base_path, metadata = list()) {
  # Ensure directory exists
  dir.create(dirname(base_path), showWarnings = FALSE, recursive = TRUE)
  
  # Save model as RDS (models can't be saved as CSV directly)
  rds_path <- paste0(base_path, ".rds")
  rds_success <- tryCatch({
    saveRDS(model, rds_path)
    TRUE
  }, error = function(e) {
    warning(sprintf("Failed to save model RDS '%s': %s", rds_path, e$message))
    FALSE
  })
  
  # Save metadata as CSV for human readability
  csv_path <- paste0(base_path, "_metadata.csv")
  csv_success <- FALSE
  
  if (length(metadata) > 0) {
    csv_success <- tryCatch({
      # Convert metadata to data frame
      metadata_df <- data.frame(
        key = names(metadata),
        value = as.character(metadata),
        stringsAsFactors = FALSE
      )
      write.csv(metadata_df, csv_path, row.names = FALSE)
      TRUE
    }, error = function(e) {
      warning(sprintf("Failed to save metadata CSV '%s': %s", csv_path, e$message))
      FALSE
    })
  }
  
  # Return results
  result <- list(
    rds_path = if (rds_success) rds_path else NULL,
    csv_path = if (csv_success) csv_path else NULL,
    rds_success = rds_success,
    csv_success = csv_success
  )
  
  if (rds_success) {
    message(sprintf("Saved model: %s.rds%s", basename(base_path), 
                   if (csv_success) " + metadata.csv" else ""))
  } else {
    stop(sprintf("Failed to save model: %s", basename(base_path)))
  }
  
  return(result)
}

##' Load data with CSV preference for CatBoost workflows
##' @param base_path Base file path without extension
##' @param csv_options List of additional options for read.csv
##' @return Data frame
##' @examples
##' data <- load_catboost_format("model_data/final_data")
##' # Tries: final_data.csv first, then final_data.rds
load_catboost_format <- function(base_path, csv_options = list()) {
  # For CatBoost, prefer CSV over RDS
  load_dual_format(base_path, prefer_rds = FALSE, csv_options = csv_options)
}

##' Check if we're in a CatBoost context
##' @return Logical indicating if CatBoost is being used
is_catboost_context <- function() {
  # Check environment variables and call stack for CatBoost indicators
  catboost_env <- any(grepl("CATBOOST", names(Sys.getenv()), ignore.case = TRUE))
  
  # Check if we're in a CatBoost function call
  call_stack <- sys.calls()
  catboost_calls <- any(sapply(call_stack, function(call) {
    if (is.call(call) && length(call) > 0) {
      func_name <- as.character(call[[1]])
      any(grepl("catboost|fit_catboost", func_name, ignore.case = TRUE))
    } else {
      FALSE
    }
  }))
  
  return(catboost_env || catboost_calls)
}
