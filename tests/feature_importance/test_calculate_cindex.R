# Quick test for calculate_cindex()

# Helper function (copied from notebook)
calculate_cindex <- function(time, status, risk_scores) {
  valid_idx <- !is.na(time) & !is.na(status) & !is.na(risk_scores) &
    is.finite(time) & is.finite(risk_scores) & time > 0

  cat("  [cindex] n =", length(time),
      " valid =", sum(valid_idx),
      " events =", sum(status[valid_idx]), "\n")

  if (sum(valid_idx) < 10) {
    return(NA_real_)
  }

  time_clean   <- time[valid_idx]
  status_clean <- status[valid_idx]
  score_clean  <- risk_scores[valid_idx]

  if (sum(status_clean) == 0) {
    return(NA_real_)
  }

  if (length(unique(score_clean)) == 1) {
    return(0.5)
  }

  c_try <- tryCatch({
    c1 <- survival::concordance(survival::Surv(time_clean, status_clean) ~ score_clean)$concordance
    c2 <- survival::concordance(survival::Surv(time_clean, status_clean) ~ -score_clean)$concordance
    as.numeric(max(c1, c2))
  }, error = function(e) {
    NA_real_
  })
  if (!is.na(c_try)) return(c_try)

  c_try2 <- tryCatch({
    sc1 <- survival::survConcordance(survival::Surv(time_clean, status_clean) ~ score_clean)
    sc2 <- survival::survConcordance(survival::Surv(time_clean, status_clean) ~ -score_clean)
    if (!is.null(sc1$conc)) {
      c1 <- sc1$conc / sc1$n
      c2 <- sc2$conc / sc2$n
      as.numeric(max(c1, c2))
    } else if (!is.null(sc1$concordance)) {
      as.numeric(max(sc1$concordance, sc2$concordance))
    } else {
      NA_real_
    }
  }, error = function(e) NA_real_)
  if (!is.na(c_try2)) return(c_try2)

  c_try3 <- tryCatch({
    if (requireNamespace("riskRegression", quietly = TRUE)) {
      score_data <- data.frame(time = as.numeric(time_clean), status = as.integer(status_clean))
      eval_obj <- tryCatch({
        riskRegression::Score(object = list(PRED = as.matrix(score_clean)),
                              formula = survival::Surv(time, status) ~ 1,
                              data = score_data,
                              times = median(time_clean, na.rm = TRUE),
                              summary = "risks",
                              metrics = "auc",
                              se.fit = FALSE)
      }, error = function(e) NULL)
      if (!is.null(eval_obj) && !is.null(eval_obj$AUC$score)) {
        auc_tab <- eval_obj$AUC$score
        if ("times" %in% names(auc_tab)) {
          this_row <- which.min(abs(auc_tab$times - median(time_clean, na.rm = TRUE)))
        } else {
          this_row <- 1L
        }
        return(as.numeric(auc_tab$AUC[this_row]))
      }
    }
    NA_real_
  }, error = function(e) NA_real_)
  if (!is.na(c_try3)) return(c_try3)

  harrell_sample_c <- function(timev, statusv, scorev, max_sample = 2000) {
    n <- length(timev)
    if (n > max_sample) {
      set.seed(42)
      idx <- sample(seq_len(n), max_sample)
      timev <- timev[idx]; statusv <- statusv[idx]; scorev <- scorev[idx]
      n <- max_sample
    }
    usable <- 0L; concordant <- 0L; ties <- 0L
    for (i in seq_len(n - 1)) {
      for (j in seq.int(i + 1, n)) {
        if (statusv[i] == 1 && timev[i] < timev[j]) {
          usable <- usable + 1L
          if (scorev[i] > scorev[j]) concordant <- concordant + 1L
          else if (scorev[i] == scorev[j]) ties <- ties + 1L
        } else if (statusv[j] == 1 && timev[j] < timev[i]) {
          usable <- usable + 1L
          if (scorev[j] > scorev[i]) concordant <- concordant + 1L
          else if (scorev[i] == scorev[j]) ties <- ties + 1L
        }
      }
    }
    if (usable == 0L) return(NA_real_)
    (concordant + 0.5 * ties) / usable
  }

  c_final <- tryCatch({
    harrell_sample_c(time_clean, status_clean, score_clean, max_sample = 2000)
  }, error = function(e) NA_real_)

  if (is.na(c_final)) return(NA_real_)
  return(as.numeric(c_final))
}

# Run a few synthetic tests
suppressPackageStartupMessages(library(survival))
cat("\n=== Synthetic tests for calculate_cindex() ===\n")
set.seed(1)
n <- 1000
time <- rexp(n, rate = 0.2)
status <- rbinom(n, 1, prob = 0.2)
score <- rnorm(n)
res1 <- calculate_cindex(time, status, score)
cat("Test 1 (random score) C-index:", res1, "\n")

# Test with monotonic score (higher score for earlier events)
score2 <- -time + rnorm(n, sd = 0.1)
res2 <- calculate_cindex(time, status, score2)
cat("Test 2 (score correlated with time) C-index:", res2, "\n")

# Test with constant score
score_const <- rep(1, n)
res3 <- calculate_cindex(time, status, score_const)
cat("Test 3 (constant score) C-index (expect 0.5):", res3, "\n")

# Small sample (<10) -> NA
res4 <- calculate_cindex(time[1:5], status[1:5], score[1:5])
cat("Test 4 (small sample) C-index (expect NA):", res4, "\n")
