##' Data cleaning and preprocessing utilities
##' 
##' Collection of helper functions for data preparation and cleaning

# Re-export commonly used cleaning functions
clean_chr <- get("clean_chr", envir = globalenv())
clean_phts <- get("clean_phts", envir = globalenv())

##' Standardized data validation
##' @param data Input dataset
##' @param required_cols Required column names
##' @param time_col Name of time column
##' @param status_col Name of status column
validate_survival_data <- function(data, required_cols = c("time", "status"), 
                                   time_col = "time", status_col = "status") {
  # Check required columns
  missing_cols <- setdiff(required_cols, names(data))
  if (length(missing_cols)) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }
  
  # Validate survival data
  if (any(data[[time_col]] <= 0, na.rm = TRUE)) {
    warning("Non-positive survival times detected")
  }
  
  if (!all(data[[status_col]] %in% c(0, 1), na.rm = TRUE)) {
    warning("Status column should contain only 0/1 values")
  }
  
  invisible(TRUE)
}

##' Standardized missing data summary
##' @param data Input dataset
summarize_missingness <- function(data) {
  data %>%
    summarise_all(~sum(is.na(.))) %>%
    pivot_longer(everything(), names_to = "variable", values_to = "n_missing") %>%
    mutate(
      prop_missing = n_missing / nrow(data),
      n_complete = nrow(data) - n_missing
    ) %>%
    arrange(desc(prop_missing))
}