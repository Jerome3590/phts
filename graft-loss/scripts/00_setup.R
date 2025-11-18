# Use centralized configuration system with smart package management
source(file.path("scripts", "config.R"))

# Fast setup for interactive sessions (minimal = TRUE for speed)
# Set minimal = FALSE for full pipeline runs
is_interactive <- interactive() || Sys.getenv("JUPYTER_RUNTIME_DIR") != ""
initialize_pipeline(
  load_functions = TRUE,
  minimal_packages = is_interactive,
  quiet = !is_interactive
)

# Load utility modules
source(here::here("R", "utils", "data_utils.R"))
source(here::here("R", "utils", "model_utils.R"))
source(here::here("R", "utils", "parallel_utils.R"))

message("Enhanced setup complete with centralized configuration.")

