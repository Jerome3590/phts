##' XGBoost Helper Functions (Backward Compatibility)
##' 
##' Legacy wrapper functions for XGBoost survival modeling.
##' These provide backward compatibility for older code that references sgb_* functions.

##' Create XGBoost DMatrix from data and labels
##' @param data Training data (matrix or data frame)
##' @param label Response labels (time or survival object)
##' @return xgb.DMatrix object
sgb_data <- function(data, label = NULL) {
  # Convert data to matrix if needed
  if (is.data.frame(data)) {
    data <- as.matrix(data)
  }
  
  # Create DMatrix
  if (!is.null(label)) {
    xgboost::xgb.DMatrix(data = data, label = label)
  } else {
    xgboost::xgb.DMatrix(data = data)
  }
}

##' Fit XGBoost model (legacy wrapper)
##' @param sgb_df xgb.DMatrix object created by sgb_data()
##' @param nrounds Maximum number of boosting rounds
##' @param params List of XGBoost parameters
##' @param verbose Verbosity level (0 = silent)
##' @param ... Additional parameters passed to xgb.train()
##' @return Trained XGBoost model
sgb_fit <- function(sgb_df, nrounds = 100, params = list(), verbose = 0, ...) {
  # Ensure required parameters are set
  if (is.null(params$objective)) {
    params$objective <- "survival:aft"
  }
  if (is.null(params$eval_metric)) {
    params$eval_metric <- "aft-nloglik"
  }
  
  # Train model
  xgboost::xgb.train(
    data = sgb_df,
    nrounds = nrounds,
    params = params,
    verbose = verbose,
    ...
  )
}

