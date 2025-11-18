# Test script to compare RSF and CatBoost prediction formats
# This will help identify why Score() works for CatBoost but not RSF

library(survival)
library(ranger)
library(riskRegression)
library(prodlim)

cat("=== Testing RSF vs CatBoost Prediction Formats ===\n\n")

# Create dummy survival data
set.seed(42)
n <- 100
time <- runif(n, 0.1, 5)  # Survival times in years
status <- rbinom(n, 1, 0.3)  # 30% event rate

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
cat("=== RSF Model ===\n")
rsf_model <- ranger(
  Surv(time, status) ~ x1 + x2 + x3,
  data = rsf_data,
  num.trees = 100,
  importance = 'permutation'
)

# Define ranger_predictrisk function (matching our script)
ranger_predictrisk <- function(object, newdata, times) {
  cat("  [ranger_predictrisk] Called with times =", times, "\n")
  cat("  [ranger_predictrisk] unique.death.times range:", 
      paste(range(object$unique.death.times, na.rm=TRUE), collapse=" to "), "\n")
  
  ptemp <- NULL
  
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
  
  cat("  [ranger_predictrisk] Survival matrix dim:", paste(dim(ptemp), collapse="x"), "\n")
  
  pos <- prodlim::sindex(
    jump.times = object$unique.death.times,
    eval.times = times
  )
  
  cat("  [ranger_predictrisk] sindex pos:", paste(pos, collapse=", "), "\n")
  
  p <- cbind(1, ptemp)[, pos + 1, drop = FALSE]
  
  cat("  [ranger_predictrisk] Risk matrix dim:", paste(dim(p), collapse="x"), "\n")
  cat("  [ranger_predictrisk] Risk range:", paste(range(1 - p, na.rm=TRUE), collapse=" to "), "\n")
  
  1 - p
}

horizon <- 1  # 1 year

cat("\nGetting RSF predictions at horizon =", horizon, "\n")
risk_pred <- ranger_predictrisk(rsf_model, newdata = rsf_data, times = horizon)

cat("\nRSF Raw prediction:\n")
cat("  Class:", paste(class(risk_pred), collapse=", "), "\n")
cat("  Type:", typeof(risk_pred), "\n")
cat("  Dim:", paste(dim(risk_pred), collapse="x"), "\n")
cat("  First 5 values:", paste(head(risk_pred[, 1], 5), collapse=", "), "\n")
cat("  Range:", paste(range(risk_pred[, 1], na.rm=TRUE), collapse=" to "), "\n")

# Extract as vector
rsf_predictions <- if (is.matrix(risk_pred)) {
  as.numeric(risk_pred[, 1])
} else {
  as.numeric(risk_pred)
}

cat("\nRSF After extraction:\n")
cat("  Class:", paste(class(rsf_predictions), collapse=", "), "\n")
cat("  Length:", length(rsf_predictions), "\n")
cat("  Range:", paste(range(rsf_predictions, na.rm=TRUE), collapse=" to "), "\n")

# Create score data
score_data <- data.frame(
  time   = as.numeric(rsf_data$time),
  status = as.integer(rsf_data$status)
)

# Test Score() with RSF predictions
cat("\n=== Testing riskRegression::Score() with RSF predictions ===\n")
cat("Before Score():\n")
cat("  score_data rows:", nrow(score_data), "\n")
cat("  rsf_predictions length:", length(rsf_predictions), "\n")
pred_matrix <- as.matrix(rsf_predictions)
cat("  as.matrix() dim:", paste(dim(pred_matrix), collapse="x"), "\n")
cat("  as.matrix() class:", paste(class(pred_matrix), collapse=", "), "\n")
cat("  horizon:", horizon, "\n")

tryCatch({
  result_rsf <- riskRegression::Score(
    object  = list(RSF = pred_matrix),
    formula = survival::Surv(time, status) ~ 1,
    data    = score_data,
    times   = horizon,
    summary = "risks",
    metrics = "auc",
    se.fit  = FALSE
  )
  cat("\n  SUCCESS! RSF C-index:", result_rsf$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("\n  ERROR:", e$message, "\n")
  cat("  Error class:", class(e), "\n")
})

# Now simulate CatBoost predictions (signed-time)
cat("\n=== Simulating CatBoost Predictions ===\n")
# CatBoost predicts signed-time: positive for events, negative for censored
catboost_signed_time <- ifelse(status == 1, time, -time) + rnorm(n, 0, 0.1)
cat("  Signed-time range:", paste(range(catboost_signed_time, na.rm=TRUE), collapse=" to "), "\n")

# Convert to risk scores (negative = higher risk)
catboost_risk_scores <- -as.numeric(catboost_signed_time)

cat("\nCatBoost risk scores:\n")
cat("  Class:", paste(class(catboost_risk_scores), collapse=", "), "\n")
cat("  Length:", length(catboost_risk_scores), "\n")
cat("  Range:", paste(range(catboost_risk_scores, na.rm=TRUE), collapse=" to "), "\n")

# Test Score() with CatBoost predictions
cat("\n=== Testing riskRegression::Score() with CatBoost predictions ===\n")
catboost_matrix <- as.matrix(catboost_risk_scores)
cat("  as.matrix() dim:", paste(dim(catboost_matrix), collapse="x"), "\n")
cat("  as.matrix() class:", paste(class(catboost_matrix), collapse=", "), "\n")

tryCatch({
  result_catboost <- riskRegression::Score(
    object  = list(CatBoost = catboost_matrix),
    formula = survival::Surv(time, status) ~ 1,
    data    = score_data,
    times   = horizon,
    summary = "risks",
    metrics = "auc",
    se.fit  = FALSE
  )
  cat("\n  SUCCESS! CatBoost C-index:", result_catboost$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("\n  ERROR:", e$message, "\n")
  cat("  Error class:", class(e), "\n")
})

# Compare structures
cat("\n=== Comparison ===\n")
cat("RSF predictions:\n")
cat("  Type:", typeof(rsf_predictions), "\n")
cat("  Class:", paste(class(rsf_predictions), collapse=", "), "\n")
cat("  Matrix type:", typeof(pred_matrix), "\n")
cat("  Matrix class:", paste(class(pred_matrix), collapse=", "), "\n")
cat("  Matrix attributes:", paste(names(attributes(pred_matrix)), collapse=", "), "\n")

cat("\nCatBoost predictions:\n")
cat("  Type:", typeof(catboost_risk_scores), "\n")
cat("  Class:", paste(class(catboost_risk_scores), collapse=", "), "\n")
cat("  Matrix type:", typeof(catboost_matrix), "\n")
cat("  Matrix class:", paste(class(catboost_matrix), collapse=", "), "\n")
cat("  Matrix attributes:", paste(names(attributes(catboost_matrix)), collapse=", "), "\n")

cat("\n=== Summary ===\n")
cat("If both work, the format is correct.\n")
cat("If RSF fails but CatBoost works, check the differences above.\n")

