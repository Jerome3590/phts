# Test script specifically for RSF predictions format
# Mimics the actual scenario from replicate_20_features.R

library(survival)
library(ranger)
library(riskRegression)
library(prodlim)

cat("=== Testing RSF-specific Score() format ===\n\n")

# Create dummy survival data similar to actual data
set.seed(42)
n <- 100
time <- runif(n, 0.001, 15)  # Similar to actual time range
status <- rbinom(n, 1, 0.2)  # ~20% event rate

# Create data frame for RSF
rsf_data <- data.frame(
  x1 = rnorm(n),
  x2 = rnorm(n),
  x3 = rnorm(n),
  time = as.numeric(time),
  status = as.integer(status)
)

cat("Data:\n")
cat("  n =", n, "\n")
cat("  Events =", sum(status), "\n")
cat("  Time range:", range(time), "\n\n")

# Fit RSF model
cat("Fitting RSF model...\n")
rsf_model <- ranger(
  Surv(time, status) ~ x1 + x2 + x3,
  data = rsf_data,
  num.trees = 100,
  importance = 'permutation'
)

# Get predictions using ranger_predictrisk (matching our function)
ranger_predictrisk <- function(object, newdata, times) {
  ptemp <- NULL
  
  # Try several predict() interfaces
  ptemp <- tryCatch({
    predict(object, new_data = newdata, type = "response")$survival
  }, error = function(e) NULL)
  
  if (is.null(ptemp)) {
    ptemp <- tryCatch({
      predict(object, data = newdata, type = "response")$survival
    }, error = function(e) NULL)
  }
  
  if (is.null(ptemp)) {
    ptemp <- tryCatch({
      predict(object, newdata = newdata, type = "response")$survival
    }, error = function(e) NULL)
  }
  
  if (is.null(ptemp)) {
    stop("Could not call predict() on ranger object")
  }
  
  pos <- prodlim::sindex(
    jump.times = object$unique.death.times,
    eval.times = times
  )
  
  p <- cbind(1, ptemp)[, pos + 1, drop = FALSE]
  1 - p  # Return risk
}

horizon <- 1  # 1 year

cat("Getting risk predictions at horizon =", horizon, "\n")
risk_pred <- ranger_predictrisk(rsf_model, newdata = rsf_data, times = horizon)

cat("  Prediction type:", class(risk_pred), "\n")
cat("  Prediction dimensions:", if(is.matrix(risk_pred)) paste(dim(risk_pred), collapse="x") else length(risk_pred), "\n")
cat("  Prediction range:", range(risk_pred, na.rm = TRUE), "\n\n")

# Extract as vector (matching our code)
rsf_predictions <- if (is.matrix(risk_pred)) {
  as.numeric(risk_pred[, 1])
} else {
  as.numeric(risk_pred)
}

cat("After extraction:\n")
cat("  Type:", class(rsf_predictions), "\n")
cat("  Length:", length(rsf_predictions), "\n")
cat("  Range:", range(rsf_predictions, na.rm = TRUE), "\n")
cat("  Any NA:", any(is.na(rsf_predictions)), "\n")
cat("  Any Inf:", any(is.infinite(rsf_predictions)), "\n\n")

# Test different Score() formats
cat("=== Test 1: Vector (as in current code) ===\n")
score_data <- data.frame(
  time   = as.numeric(rsf_data$time),
  status = as.integer(rsf_data$status)
)

tryCatch({
  result1 <- riskRegression::Score(
    object  = list(RSF = as.matrix(rsf_predictions)),
    formula = survival::Surv(time, status) ~ 1,
    data    = score_data,
    times   = horizon,
    summary = "risks",
    metrics = "auc",
    se.fit  = FALSE
  )
  cat("  SUCCESS!\n")
  cat("  AUC:", result1$AUC$score$AUC[1], "\n")
  cat("  AUC table structure:\n")
  print(result1$AUC$score)
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
  cat("  Error class:", class(e), "\n")
})

cat("\n=== Test 2: Vector without as.matrix() ===\n")
tryCatch({
  result2 <- riskRegression::Score(
    object  = list(RSF = rsf_predictions),  # Just vector, no matrix
    formula = survival::Surv(time, status) ~ 1,
    data    = score_data,
    times   = horizon,
    summary = "risks",
    metrics = "auc",
    se.fit  = FALSE
  )
  cat("  SUCCESS!\n")
  cat("  AUC:", result2$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 3: Check data types ===\n")
cat("  score_data$time type:", class(score_data$time), "\n")
cat("  score_data$status type:", class(score_data$status), "\n")
cat("  rsf_predictions type:", class(rsf_predictions), "\n")
cat("  as.matrix(rsf_predictions) type:", class(as.matrix(rsf_predictions)), "\n")
cat("  as.matrix(rsf_predictions) dim:", paste(dim(as.matrix(rsf_predictions)), collapse="x"), "\n")

cat("\n=== Test 4: Check for any special values ===\n")
cat("  Unique time values (first 10):", head(unique(score_data$time), 10), "\n")
cat("  Unique status values:", unique(score_data$status), "\n")
cat("  Status sum:", sum(score_data$status), "\n")
cat("  Any zero times:", any(score_data$time == 0), "\n")
cat("  Any negative times:", any(score_data$time < 0), "\n")

cat("\n=== Test 5: Try with exact format from error scenario ===\n")
# Simulate what might be happening in the actual code
tryCatch({
  # Ensure everything is exactly as it would be in the real scenario
  time_vec <- as.numeric(rsf_data$time)
  status_vec <- as.integer(rsf_data$status)
  pred_vec <- as.numeric(rsf_predictions)
  
  # Check lengths match
  if (length(time_vec) != length(status_vec) || length(status_vec) != length(pred_vec)) {
    cat("  ERROR: Length mismatch!\n")
    cat("    time:", length(time_vec), "status:", length(status_vec), "pred:", length(pred_vec), "\n")
  } else {
    cat("  Lengths match:", length(time_vec), "\n")
    
    score_data_clean <- data.frame(
      time   = time_vec,
      status = status_vec
    )
    
    result5 <- riskRegression::Score(
      object  = list(RSF = as.matrix(pred_vec)),
      formula = survival::Surv(time, status) ~ 1,
      data    = score_data_clean,
      times   = horizon,
      summary = "risks",
      metrics = "auc",
      se.fit  = FALSE
    )
    cat("  SUCCESS!\n")
    cat("  AUC:", result5$AUC$score$AUC[1], "\n")
  }
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
  print(traceback())
})

cat("\n=== Summary ===\n")
cat("If all tests pass, the format is correct.\n")
cat("The 'Cannot assign response type' error might be due to:\n")
cat("  1. Data type mismatches\n")
cat("  2. Length mismatches\n")
cat("  3. Special values (NA, Inf, etc.)\n")
cat("  4. Version-specific issues with riskRegression\n")

