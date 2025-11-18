# Create a minimal test model for testing 07_generate_outputs.R
library(here)

# Create a simple ORSF model object
test_model <- list(
  model = "test_orsf",
  type = "ORSF",
  variables = c("prim_dx", "tx_mcsd", "chd_sv", "hxsurg", "txsa_r"),
  created_at = Sys.time()
)

# Add some basic methods that the script might expect
test_model$predict <- function(newdata, times = 1) {
  # Return random predictions for testing
  rep(runif(1, 0.1, 0.9), nrow(newdata))
}

# Save the test model
saveRDS(test_model, 'models/unknown/final_model.rds')

cat("Created test model: models/unknown/final_model.rds\n")
