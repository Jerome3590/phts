# Safe test: use only the pure-R sampled Harrell's C fallback (no compiled survival calls)

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

# Synthetic data
set.seed(1)
n <- 500
time <- rexp(n, rate = 0.2)
status <- rbinom(n, 1, prob = 0.2)
score <- rnorm(n)

cat("Safe test using sampled Harrell's C fallback\n")
res <- harrell_sample_c(time, status, score, max_sample = 2000)
cat("Result:", res, "\n")

# Monotonic score
score2 <- -time + rnorm(n, sd = 0.1)
res2 <- harrell_sample_c(time, status, score2)
cat("Result (correlated score):", res2, "\n")

# Constant score -> NA
res3 <- harrell_sample_c(time, status, rep(1, n))
cat("Result (constant score, expect NA):", res3, "\n")
