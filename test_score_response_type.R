# Investigate the "Cannot assign response type" error
# Compare working vs non-working cases

library(survival)
library(riskRegression)

cat("=== Investigating 'Cannot assign response type' error ===\n\n")

set.seed(42)
n <- 100
time <- runif(n, 0.001, 15)
status <- rbinom(n, 1, 0.2)

score_data <- data.frame(
  time = as.numeric(time),
  status = as.integer(status)
)

# Working case: random risk scores 0-1
risk_scores_working <- runif(n, 0, 1)

# Non-working case: RSF-like risk scores (smaller range)
risk_scores_rsf <- runif(n, 0, 0.3)  # Smaller range like RSF

cat("=== Test 1: Working case (random 0-1) ===\n")
cat("  Range:", range(risk_scores_working), "\n")
tryCatch({
  result1 <- riskRegression::Score(
    object  = list(Model = as.matrix(risk_scores_working)),
    formula = Surv(time, status) ~ 1,
    data    = score_data,
    times   = 1,
    summary = "risks",
    metrics = "auc",
    se.fit  = FALSE
  )
  cat("  SUCCESS! AUC:", result1$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 2: RSF-like scores (smaller range) ===\n")
cat("  Range:", range(risk_scores_rsf), "\n")
tryCatch({
  result2 <- riskRegression::Score(
    object  = list(Model = as.matrix(risk_scores_rsf)),
    formula = Surv(time, status) ~ 1,
    data    = score_data,
    times   = 1,
    summary = "risks",
    metrics = "auc",
    se.fit  = FALSE
  )
  cat("  SUCCESS! AUC:", result2$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 3: Try without summary='risks' ===\n")
tryCatch({
  result3 <- riskRegression::Score(
    object  = list(Model = as.matrix(risk_scores_rsf)),
    formula = Surv(time, status) ~ 1,
    data    = score_data,
    times   = 1,
    metrics = "auc",
    se.fit  = FALSE
  )
  cat("  SUCCESS! AUC:", result3$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 4: Try with cause parameter ===\n")
tryCatch({
  result4 <- riskRegression::Score(
    object  = list(Model = as.matrix(risk_scores_rsf)),
    formula = Surv(time, status) ~ 1,
    data    = score_data,
    times   = 1,
    summary = "risks",
    metrics = "auc",
    cause    = 1,
    se.fit  = FALSE
  )
  cat("  SUCCESS! AUC:", result4$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 5: Check if it's about the matrix being column vs row ===\n")
# Try as column vector explicitly
risk_matrix_col <- matrix(risk_scores_rsf, ncol = 1)
cat("  Matrix dim:", paste(dim(risk_matrix_col), collapse="x"), "\n")
tryCatch({
  result5 <- riskRegression::Score(
    object  = list(Model = risk_matrix_col),
    formula = Surv(time, status) ~ 1,
    data    = score_data,
    times   = 1,
    summary = "risks",
    metrics = "auc",
    se.fit  = FALSE
  )
  cat("  SUCCESS! AUC:", result5$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 6: Try with response.type parameter ===\n")
# Maybe we need to explicitly specify response type
tryCatch({
  result6 <- riskRegression::Score(
    object       = list(Model = as.matrix(risk_scores_rsf)),
    formula      = Surv(time, status) ~ 1,
    data         = score_data,
    times        = 1,
    summary      = "risks",
    metrics      = "auc",
    response.type = "risk",
    se.fit       = FALSE
  )
  cat("  SUCCESS! AUC:", result6$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
  # Check if response.type is a valid parameter
  cat("  Checking if response.type is valid parameter...\n")
  cat("  Formals:", paste(names(formals(riskRegression::Score.list)), collapse=", "), "\n")
})

cat("\n=== Test 7: Check Score.list method directly ===\n")
# Maybe we need to call Score.list directly
tryCatch({
  result7 <- riskRegression::Score.list(
    object  = list(Model = as.matrix(risk_scores_rsf)),
    formula = Surv(time, status) ~ 1,
    data    = score_data,
    times   = 1,
    summary = "risks",
    metrics = "auc",
    se.fit  = FALSE
  )
  cat("  SUCCESS! AUC:", result7$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
  # Print more details
  cat("  Error details:\n")
  print(str(e))
})

cat("\n=== Test 8: Compare actual RSF predictions structure ===\n")
# Load ranger and create actual RSF predictions
library(ranger)
library(prodlim)

rsf_data <- score_data
rsf_data$x1 <- rnorm(n)
rsf_data$x2 <- rnorm(n)
rsf_data$x3 <- rnorm(n)

rsf_model <- ranger(
  Surv(time, status) ~ x1 + x2 + x3,
  data = rsf_data,
  num.trees = 50
)

# Get predictions
pred_result <- predict(rsf_model, data = rsf_data, type = "response")
cat("  Prediction result structure:\n")
print(str(pred_result))

# Try using survival probabilities directly
if (!is.null(pred_result$survival)) {
  cat("\n  Trying with survival probabilities at horizon...\n")
  # Find column closest to horizon
  unique_times <- rsf_model$unique.death.times
  pos <- prodlim::sindex(jump.times = unique_times, eval.times = 1)
  surv_at_horizon <- cbind(1, pred_result$survival)[, pos + 1]
  risk_at_horizon <- 1 - surv_at_horizon
  
  cat("  Risk range:", range(risk_at_horizon), "\n")
  
  tryCatch({
    result8 <- riskRegression::Score(
      object  = list(RSF = as.matrix(risk_at_horizon)),
      formula = Surv(time, status) ~ 1,
      data    = score_data,
      times   = 1,
      summary = "risks",
      metrics = "auc",
      se.fit  = FALSE
    )
    cat("  SUCCESS! AUC:", result8$AUC$score$AUC[1], "\n")
  }, error = function(e) {
    cat("  ERROR:", e$message, "\n")
  })
}

cat("\n=== Summary ===\n")
cat("If error persists, it might be a version-specific issue.\n")
cat("Consider using survival::concordance() as fallback.\n")

