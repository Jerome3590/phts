##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##'
##' @param trn 
##' @param tst 
##' @param n_predictors 
##' @param predict_horizon 
##' 
fit_xgb <- function(trn,
                    vars,
                    tst = NULL,
                    predict_horizon = NULL){

  # Guard: ensure all requested predictor columns exist
  missing_cols <- setdiff(vars, names(trn))
  if (length(missing_cols)) {
    stop(sprintf("fit_xgb: missing predictor columns: %s", paste(missing_cols, collapse=", ")), call. = FALSE)
  }

  # Extract predictor frame
  x_frame <- dplyr::select(trn, dplyr::all_of(vars))

  # Handle non-numeric columns instead of failing early: coerce factors/characters to integer codes.
  non_numeric <- names(x_frame)[!vapply(x_frame, is.numeric, logical(1))]
  if (length(non_numeric)) {
    message("fit_xgb: coercing non-numeric predictors to integer codes: ", paste(non_numeric, collapse=", "))
    for (nm in non_numeric) {
      # Convert factor/character/logical to integer codes (stable ordering for factor levels)
      if (is.factor(x_frame[[nm]])) {
        x_frame[[nm]] <- as.integer(x_frame[[nm]])
      } else if (is.character(x_frame[[nm]])) {
        x_frame[[nm]] <- as.integer(factor(x_frame[[nm]]))
      } else if (is.logical(x_frame[[nm]])) {
        x_frame[[nm]] <- as.integer(x_frame[[nm]])
      } else {
        # Fallback: best-effort numeric coercion
        suppressWarnings(x_frame[[nm]] <- as.numeric(x_frame[[nm]]))
      }
    }
  }

  # Build training matrix limited to vars for clarity (avoid unintended columns)
  trn_x <- as.matrix(x_frame)
  trn_y <- as.matrix(select(trn, c(time, status)))
  
  xgb_label <- trn_y[, 1]
  censored <- trn_y[, 2] == 0
  xgb_label[censored] <- xgb_label[censored] * (-1)
  
  # Threads: honor MC_WORKER_THREADS for sgb/xgboost backend
  threads <- suppressWarnings(as.integer(Sys.getenv("MC_WORKER_THREADS", unset = "1")))
  if (!is.finite(threads) || threads < 1) threads <- 1L
  nrounds <- suppressWarnings(as.integer(Sys.getenv("XGB_NROUNDS", unset = "500")))
  if (!is.finite(nrounds) || nrounds < 10) nrounds <- 500L

  model <- sgb_fit(
  sgb_df = sgb_data(trn_x[, vars, drop = FALSE], xgb_label),
    verbose = 0,
    params = list(
      eta = 0.01,
      max_depth = 3,
      gamma = 1/2,
      min_child_weight = 2,
      subsample = 1/2,
      colsample_bynode = 1/2,
      objective = "survival:cox",
      eval_metric = "cox-nloglik",
      nthread = threads,
      nrounds = nrounds
    )
  ) 
  
  if(is.null(tst)) return(model)
  
  if(is.null(predict_horizon)) stop("specify prediction horizon", call. = F)
  
  1 - predict(
    model,
    new_data = as.matrix(tst[, vars]),
    eval_times = predict_horizon
  )
  
}
