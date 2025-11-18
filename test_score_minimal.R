# Minimal test to understand Score() requirements
library(survival)
library(riskRegression)

set.seed(42)
n <- 50
time <- runif(n, 0.1, 5)
status <- rbinom(n, 1, 0.3)
risk_scores <- runif(n, 0, 1)

# Test 1: Basic working case (from earlier tests)
cat("Test 1: Basic vector\n")
tryCatch({
  result1 <- riskRegression::Score(
    object = list(Model = risk_scores),
    formula = Surv(time, status) ~ 1,
    data = data.frame(time = time, status = status),
    times = 1,
    metrics = "auc"
  )
  cat("  SUCCESS! AUC:", result1$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

# Test 2: With matrix
cat("\nTest 2: Matrix\n")
tryCatch({
  result2 <- riskRegression::Score(
    object = list(Model = as.matrix(risk_scores)),
    formula = Surv(time, status) ~ 1,
    data = data.frame(time = time, status = status),
    times = 1,
    metrics = "auc"
  )
  cat("  SUCCESS! AUC:", result2$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

# Test 3: With summary="risks"
cat("\nTest 3: With summary='risks'\n")
tryCatch({
  result3 <- riskRegression::Score(
    object = list(Model = risk_scores),
    formula = Surv(time, status) ~ 1,
    data = data.frame(time = time, status = status),
    times = 1,
    summary = "risks",
    metrics = "auc"
  )
  cat("  SUCCESS! AUC:", result3$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

# Test 4: With summary="risks" and matrix
cat("\nTest 4: Matrix with summary='risks'\n")
tryCatch({
  result4 <- riskRegression::Score(
    object = list(Model = as.matrix(risk_scores)),
    formula = Surv(time, status) ~ 1,
    data = data.frame(time = time, status = status),
    times = 1,
    summary = "risks",
    metrics = "auc"
  )
  cat("  SUCCESS! AUC:", result4$AUC$score$AUC[1], "\n")
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
})

cat("\n=== Conclusion ===\n")
cat("If Test 1 or 2 works but 3 or 4 fails, the issue is with summary='risks'\n")
cat("If all fail, there's an environment/version issue\n")

