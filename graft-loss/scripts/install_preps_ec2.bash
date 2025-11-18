#!/usr/bin/env bash

# Minimal EC2 installer for Amazon Linux 2 - graft-loss pipeline
#
# Usage:
#   bash scripts/install_update_ec2.bash [--run] [--full]
#
# Flags:
#   --run   After install, run pipeline Steps 01–05 with speed-friendly defaults
#   --full  Use larger model sizes (slower, for fidelity) when used with --run

set -euo pipefail

RUN_STEPS=0
FULL_SIZE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run|--run-steps) RUN_STEPS=1 ; shift ;;
    --full) FULL_SIZE=1 ; shift ;;
    -h|--help)
      sed -n '1,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "[ERROR] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

echo "[STEP] Update base system"
sudo yum update -y

echo "[STEP] Core build chain"
sudo yum groupinstall -y "Development Tools"
sudo yum install -y gcc gcc-c++ gcc-gfortran make

echo "[STEP] Newer CMake (cmake3) and set it as default (needed by some packages)"
sudo yum install -y cmake3
sudo alternatives --install /usr/bin/cmake cmake /usr/bin/cmake3 30
sudo alternatives --set cmake /usr/bin/cmake3

echo "[STEP] Headers/libs commonly required by CRAN packages and rstanarm"
sudo yum install -y \
  openssl-devel libcurl-devel libxml2-devel zlib-devel bzip2-devel xz-devel \
  freetype-devel libjpeg-turbo-devel libpng-devel libtiff-devel lcms2-devel \
  ImageMagick-c++-devel ImageMagick-devel

echo "[STEP] Creating ~/.R/Makevars with optimized compile flags"
mkdir -p ~/.R
cat > ~/.R/Makevars <<'EOF'
CXX14 = g++ -std=gnu++14
CXX17 = g++ -std=gnu++17
CXX14FLAGS = -O3 -march=native -mtune=native -fPIC
CXX17FLAGS = -O3 -march=native -mtune=native -fPIC
MAKEFLAGS = -j$(nproc)
EOF

echo "[STEP] Install critical R packages for Stan/rstanarm"
R -q -e 'options(repos = c(CRAN = "https://cloud.r-project.org")); install.packages(c("Rcpp","RcppParallel","BH","inline"), Ncpus = max(1L, parallel::detectCores()-1L))'
R -q -e 'options(repos = c(CRAN = "https://cloud.r-project.org")); install.packages(c("StanHeaders","rstan"), type = "source", Ncpus = max(1L, parallel::detectCores()-1L))'
R -q -e 'options(repos = c(CRAN = "https://cloud.r-project.org")); Sys.setenv(MAKEFLAGS = paste0("-j", max(1L, parallel::detectCores()-1L))); install.packages("rstanarm", type = "source", Ncpus = max(1L, parallel::detectCores()-1L))'
R -q -e 'options(repos = c(CRAN = "https://cloud.r-project.org")); install.packages("tidyposterior", Ncpus = max(1L, parallel::detectCores()-1L))'

echo "[STEP] Running scripts/install.R from project root"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"
mkdir -p logs data/progress
Rscript -e 'options(repos = c(CRAN = "https://cloud.r-project.org")); Sys.setenv(R_REMOTES_NO_ERRORS_FROM_WARNINGS="true"); source("scripts/install.R")' | tee logs/install_ec2_packages.log || true

echo "[STEP] Capturing R session info"
Rscript -e 'outfile <- "logs/sessionInfo_ec2_install.txt"; writeLines(capture.output(sessionInfo()), outfile); message("Wrote ", outfile)'

if [[ "$RUN_STEPS" -eq 1 ]]; then
  echo "[STEP] Running pipeline Steps 01–05"
  if [[ "$FULL_SIZE" -eq 1 ]]; then
    export ORSF_NTREES=1500 RSF_NTREES=1500 XGB_NROUNDS=1000 MC_MAX_SPLITS=400
  else
    export ORSF_NTREES=500 RSF_NTREES=500 XGB_NROUNDS=300 MC_MAX_SPLITS=200
  fi
  export MC_WORKER_THREADS=1 MC_CV=1 MC_FI=0 MC_XGB_USE_GLOBAL=1 \
         OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

  Rscript - <<'RS'
options(repos = c(CRAN = "https://cloud.r-project.org"))
library(future)
workers <- max(1L, floor(as.numeric(future::availableCores()) * 0.9))
if (future::supportsMulticore()) future::plan(multicore, workers = workers) else future::plan(multisession, workers = workers)
message(sprintf("Parallel plan workers: %d", workers))

source("scripts/01_prepare_data.R")
source("scripts/02_resampling.R")
source("scripts/03_prep_model_data.R")
source("scripts/04_fit_model.R")

Sys.setenv(SKIP_PARTIALS = "1")
source("scripts/05_generate_outputs.R")

labels <- c("full","original","covid","full_no_covid")
for (lab in labels) {
  p <- file.path("data","models", sprintf("model_mc_summary_%s_uno.csv", lab))
  if (file.exists(p)) {
    cat("\n== ", lab, " ==\n", sep = ""); print(read.csv(p, check.names = FALSE))
  } else {
    cat("\nMissing: ", p, "\n", sep = "")
  }
}
RS
fi

echo "[DONE] EC2 setup complete"
