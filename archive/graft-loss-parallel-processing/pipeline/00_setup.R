# Use centralized configuration system with smart package management
source(file.path("scripts", "R", "config.R"))

# Fast setup for interactive sessions (minimal = TRUE for speed)
# Set minimal = FALSE for full pipeline runs
is_interactive <- interactive() || Sys.getenv("JUPYTER_RUNTIME_DIR") != ""
tryCatch({
  initialize_pipeline(
    load_functions = TRUE,
    minimal_packages = is_interactive,
    quiet = !is_interactive
  )
}, error = function(e) {
  # Log full traceback and session info early so wrapper logs capture init failures
  message("ERROR during pipeline initialization: ", e$message)
  message("Traceback:")
  try(traceback(), silent = TRUE)
  message("sessionInfo:")
  try(print(sessionInfo()), silent = TRUE)
  stop(e)
})

# Load utility modules
source(here::here("scripts", "R", "utils", "data_utils.R"))
source(here::here("scripts", "R", "utils", "model_utils.R"))
source(here::here("scripts", "R", "utils", "parallel_utils.R"))

# Load model-specific configuration modules
source(here::here("scripts", "R", "aorsf_parallel_config.R"))
source(here::here("scripts", "R", "catboost_parallel_config.R"))
source(here::here("scripts", "R", "xgboost_parallel_config.R"))
source(here::here("scripts", "R", "ranger_parallel_config.R"))
source(here::here("scripts", "R", "cph_parallel_config.R"))

# Load XGBoost helpers for backward compatibility
if (file.exists(here::here("scripts", "R", "xgb_helpers.R"))) {
  source(here::here("scripts", "R", "xgb_helpers.R"))
}

message("Enhanced setup complete with centralized configuration.")

