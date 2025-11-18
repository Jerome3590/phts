# Test script to understand riskRegression::Score() format requirements
# This will help debug the "Cannot assign response type" error

library(survival)
library(riskRegression)

cat("=== Testing riskRegression::Score() with dummy data ===\n\n")

# Create dummy survival data
set.seed(42)
n <- 100
time <- runif(n, 0.1, 5)  # Survival times in years
status <- rbinom(n, 1, 0.3)  # 30% event rate
risk_scores <- runif(n, 0, 1)  # Risk scores between 0 and 1

cat("Dummy data:\n")
cat("  n =", n, "\n")
cat("  Events =", sum(status), "\n")
cat("  Time range:", range(time), "\n")
cat("  Risk score range:", range(risk_scores), "\n\n")

# Create data frame
score_data <- data.frame(
  time = as.numeric(time),
  status = as.integer(status)
)

cat("=== Test 1: Vector predictions (unnamed list) ===\n")
tryCatch({
  result1 <- riskRegression::Score(
    object = list(risk_scores),  # Unnamed list with vector
    formula = Surv(time, status) ~ 1,
    data = score_data,
    times = 1,
    summary = "risks",
    metrics = "auc",
    se.fit = FALSE
  )
  cat("  SUCCESS!\n")
  cat("  AUC:", result1$AUC$score$AUC[1], "\n")
  print(str(result1))
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 2: Named list with vector ===\n")
tryCatch({
  result2 <- riskRegression::Score(
    object = list(Model1 = risk_scores),  # Named list with vector
    formula = Surv(time, status) ~ 1,
    data = score_data,
    times = 1,
    summary = "risks",
    metrics = "auc",
    se.fit = FALSE
  )
  cat("  SUCCESS!\n")
  cat("  AUC:", result2$AUC$score$AUC[1], "\n")
  print(str(result2))
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 3: Named list with matrix (n x 1) ===\n")
tryCatch({
  result3 <- riskRegression::Score(
    object = list(Model1 = as.matrix(risk_scores)),  # Named list with matrix
    formula = Surv(time, status) ~ 1,
    data = score_data,
    times = 1,
    summary = "risks",
    metrics = "auc",
    se.fit = FALSE
  )
  cat("  SUCCESS!\n")
  cat("  AUC:", result3$AUC$score$AUC[1], "\n")
  print(str(result3))
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 4: Matrix as column vector ===\n")
tryCatch({
  risk_matrix <- matrix(risk_scores, ncol = 1)
  colnames(risk_matrix) <- "Model1"
  result4 <- riskRegression::Score(
    object = list(Model1 = risk_matrix),
    formula = Surv(time, status) ~ 1,
    data = score_data,
    times = 1,
    summary = "risks",
    metrics = "auc",
    se.fit = FALSE
  )
  cat("  SUCCESS!\n")
  cat("  AUC:", result4$AUC$score$AUC[1], "\n")
  print(str(result4))
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 5: Predictions in data frame ===\n")
tryCatch({
  score_data_with_pred <- score_data
  score_data_with_pred$risk_score <- risk_scores
  result5 <- riskRegression::Score(
    object = list(risk_score = risk_scores),
    formula = Surv(time, status) ~ 1,
    data = score_data_with_pred,
    times = 1,
    summary = "risks",
    metrics = "auc",
    se.fit = FALSE
  )
  cat("  SUCCESS!\n")
  cat("  AUC:", result5$AUC$score$AUC[1], "\n")
  print(str(result5))
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 6: Using formula with predictions ===\n")
tryCatch({
  score_data_with_pred <- score_data
  score_data_with_pred$risk_score <- risk_scores
  result6 <- riskRegression::Score(
    object = list(Model1 = risk_scores),
    formula = Surv(time, status) ~ risk_score,
    data = score_data_with_pred,
    times = 1,
    summary = "risks",
    metrics = "auc",
    se.fit = FALSE
  )
  cat("  SUCCESS!\n")
  cat("  AUC:", result6$AUC$score$AUC[1], "\n")
  print(str(result6))
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 7: Multiple time points ===\n")
tryCatch({
  result7 <- riskRegression::Score(
    object = list(Model1 = as.matrix(risk_scores)),
    formula = Surv(time, status) ~ 1,
    data = score_data,
    times = c(0.5, 1, 2),  # Multiple time points
    summary = "risks",
    metrics = "auc",
    se.fit = FALSE
  )
  cat("  SUCCESS!\n")
  cat("  AUC table:\n")
  print(result7$AUC$score)
  cat("\n  Structure:\n")
  print(str(result7))
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Test 8: Check what Score() expects (inspect function) ===\n")
cat("  Function signature:\n")
print(formals(riskRegression::Score))
cat("\n  Function body (first 50 lines):\n")
print(head(capture.output(riskRegression::Score), 50))

cat("\n=== Summary ===\n")
cat("Testing complete. Check which format works above.\n")

