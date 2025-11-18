install.packages("remotes")
remotes::install_github("bcjaeger/xgboost.surv")

# Set CRAN mirror
options(repos = "https://cloud.r-project.org")

# Define package list
pkgs <- c(
  "conflicted", "dotenv", "drake", "R.utils", "haven", "janitor", "magrittr", "here",
  "foreach", "tidyverse", "tidyposterior", "ranger",
  "survival", "rms", "obliqueRSF", "xgboost", "riskRegression",
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

# Extra checks for specific packages
if (!requireNamespace("obliqueRSF", quietly = TRUE)) {
  install.packages("obliqueRSF", quiet = TRUE)
}

if (!requireNamespace("rstanarm", quietly = TRUE)) {
  install.packages("rstanarm", quiet = TRUE)
}

# Install separately in this order
install.packages('tidymodels')
install.packages('embed')
install.packages('magick')
install.packages('gtsummary')


# Data Located here: C:\Projects\phts\data\transplant.sas7bdat
