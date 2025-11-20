##' Impute Missing Values Following Original Graft-Loss Methodology
##'
##' Missing values are imputed using the mean and mode of each continuous 
##' and categorical variable, respectively, prior to fitting prediction models.
##' Missing values in testing data are imputed using the means and modes 
##' computed in training data.
##'
##' @param data Data frame with potential missing values
##' @param train_stats Optional list of training statistics for test data imputation
##' @param continuous_vars Vector of continuous variable names
##' @param categorical_vars Vector of categorical variable names
##' @return List with imputed data and statistics used for imputation
impute_missing_values <- function(data, 
                                 train_stats = NULL, 
                                 continuous_vars = NULL, 
                                 categorical_vars = NULL) {
  
  # If no variable types specified, infer from data
  if (is.null(continuous_vars) && is.null(categorical_vars)) {
    continuous_vars <- names(data)[sapply(data, is.numeric)]
    categorical_vars <- names(data)[sapply(data, function(x) is.factor(x) || is.character(x))]
  }
  
  # Initialize statistics list
  stats <- list()
  
  # Impute continuous variables with mean
  for (var in continuous_vars) {
    if (var %in% names(data)) {
      if (is.null(train_stats)) {
        # Training data: compute mean from current data (excluding NA and Inf)
        mean_val <- mean(data[[var]][is.finite(data[[var]])], na.rm = TRUE)
        stats[[var]] <- list(type = "continuous", value = mean_val)
      } else {
        # Test data: use training-derived mean
        mean_val <- train_stats[[var]]$value
      }
      
      # Impute missing values and handle infinite values
      missing_idx <- is.na(data[[var]]) | is.infinite(data[[var]])
      if (any(missing_idx)) {
        data[[var]][missing_idx] <- mean_val
        cat(sprintf("Imputed %d missing/infinite values in %s with mean: %.3f\n", 
                   sum(missing_idx), var, mean_val))
      }
    }
  }
  
  # Impute categorical variables with mode
  for (var in categorical_vars) {
    if (var %in% names(data)) {
      if (is.null(train_stats)) {
        # Training data: compute mode from current data
        var_table <- table(data[[var]], useNA = "no")
        mode_val <- names(var_table)[which.max(var_table)]
        stats[[var]] <- list(type = "categorical", value = mode_val)
      } else {
        # Test data: use training-derived mode
        mode_val <- train_stats[[var]]$value
      }
      
      # Impute missing values
      missing_idx <- is.na(data[[var]])
      if (any(missing_idx)) {
        data[[var]][missing_idx] <- mode_val
        cat(sprintf("Imputed %d missing values in %s with mode: %s\n", 
                   sum(missing_idx), var, mode_val))
      }
    }
  }
  
  return(list(data = data, stats = stats))
}

##' Apply imputation to training and test data following original methodology
##'
##' @param train_data Training data frame
##' @param test_data Test data frame
##' @param continuous_vars Vector of continuous variable names
##' @param categorical_vars Vector of categorical variable names
##' @return List with imputed training data, imputed test data, and imputation statistics
impute_train_test_data <- function(train_data, 
                                  test_data, 
                                  continuous_vars = NULL, 
                                  categorical_vars = NULL) {
  
  cat("=== Imputing Missing Values Following Original Graft-Loss Methodology ===\n")
  
  # Step 1: Impute training data and compute statistics
  cat("Step 1: Imputing training data and computing statistics...\n")
  train_result <- impute_missing_values(train_data, 
                                       train_stats = NULL,
                                       continuous_vars = continuous_vars,
                                       categorical_vars = categorical_vars)
  
  train_imputed <- train_result$data
  train_stats <- train_result$stats
  
  # Step 2: Impute test data using training-derived statistics
  cat("Step 2: Imputing test data using training-derived statistics...\n")
  test_result <- impute_missing_values(test_data, 
                                      train_stats = train_stats,
                                      continuous_vars = continuous_vars,
                                      categorical_vars = categorical_vars)
  
  test_imputed <- test_result$data
  
  cat("=== Imputation Complete ===\n")
  
  return(list(
    train_data = train_imputed,
    test_data = test_imputed,
    imputation_stats = train_stats
  ))
}
