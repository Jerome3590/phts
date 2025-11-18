# Environment setup for EC2 - NO xgboost.surv installation
# Set CRAN mirror
options(repos = "https://cloud.r-project.org")

# Define package list (removed xgboost.surv and obliqueRSF)
pkgs <- c(
  "conflicted", "dotenv", "R.utils", "haven", "janitor", "magrittr", "here",
  "foreach", "tidyverse", "tidyposterior", "ranger",
  "survival", "rms", "riskRegression",
  "naniar", "MASS", "Hmisc", "rstanarm", "table.glue", "gtsummary", "officer",
  "glue", "flextable", "devEMF", "diagram", "paletteer", "ggdist",
  "ggsci", "cmprsk", "patchwork"
)

# Find missing packages
inst <- pkgs[!(pkgs %in% rownames(installed.packages()))]

# Install missing ones
if (length(inst)) {
  install.packages(inst, Ncpus = 2, quiet = TRUE)
}

# Install separately in this order
install.packages('tidymodels')
install.packages('embed')
install.packages('magick')
install.packages('gtsummary')

# Data Located here: C:\Projects\phts\data\transplant.sas7bdat
