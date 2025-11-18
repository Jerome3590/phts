
library(base, quietly = TRUE)
library(methods, quietly = TRUE)
library(usethis, quietly = TRUE)
library(devtools, quietly = TRUE)
library(testthat, quietly = TRUE)
library(drake, quietly = TRUE)
library(datasets, quietly = TRUE)
library(utils, quietly = TRUE)
library(grDevices, quietly = TRUE)
library(stats, quietly = TRUE)
library(conflicted, quietly = TRUE)
library(dotenv, quietly = TRUE)
library(haven, quietly = TRUE)
library(janitor, quietly = TRUE)
library(magrittr, quietly = TRUE)
library(foreach, quietly = TRUE)
library(tibble, quietly = TRUE)
library(tidyr, quietly = TRUE)
library(readr, quietly = TRUE)
library(purrr, quietly = TRUE)
library(dplyr, quietly = TRUE)
library(stringr, quietly = TRUE)
library(forcats, quietly = TRUE)
library(broom, quietly = TRUE)
library(scales, quietly = TRUE)
library(dials, quietly = TRUE)
library(recipes, quietly = TRUE)
library(rsample, quietly = TRUE)
library(survival, quietly = TRUE)
library(iterators, quietly = TRUE)
library(xgboost, quietly = TRUE)
library(xgboost.surv, quietly = TRUE)
library(ranger, quietly = TRUE)
library(obliqueRSF, quietly = TRUE)
library(riskRegression, quietly = TRUE)
library(MASS, quietly = TRUE)
library(R.methodsS3, quietly = TRUE)
library(R.oo, quietly = TRUE)
library(R.utils, quietly = TRUE)
library(glue, quietly = TRUE)
library(Hmisc, quietly = TRUE)

conflicted::conflict_prefer("roc",       "pROC")
conflicted::conflict_prefer("filter",    "dplyr")
conflicted::conflict_prefer("slice",     "dplyr")
conflicted::conflict_prefer("select",    "dplyr")
conflicted::conflict_prefer("summarise", "dplyr")
conflicted::conflict_prefer("summarize", "dplyr")
conflicted::conflict_prefer("gather",    "tidyr")
conflicted::conflict_prefer("set_names", "purrr")
conflicted::conflict_prefer("plan",      "drake")

sourceDirectory("../R")

.rslurm_func <- function(resample_iteration,
                         ftr_selector,
                         n_predictors,
                         predict_horizon = 1) {
    
    phts_all <- read_rds('../data/phts_all.rds')
    resamples <- read_rds('../data/resamples.rds')
    
    testing_index <- resamples[[resample_iteration]]
    
    .training <- phts_all[-testing_index, ]
    .testing  <- phts_all[testing_index, ]
    .recipe   <- prep(make_recipe(data = .training))
    
    trn = juice(.recipe)
    tst = bake(.recipe, new_data = .testing)
    
    vars <- switch(as.character(ftr_selector),
                   'rsf' = select_rsf(select(trn,-ID), n_predictors),
                   'xgb' = select_xgb(select(trn,-ID), n_predictors),
                   'cph' = select_cph(select(trn,-ID), n_predictors))
    
    predictions <- 
        list(rsf  = fit_rsf,
             orsf = fit_orsf, 
             xgb  = fit_xgb,
             cph  = fit_cph) %>% 
        map(do.call,
            args = list(trn = trn,
                        tst = tst,
                        vars = vars,
                        predict_horizon = predict_horizon)
        )
    
    scores <- map_dfr(.x = predictions,
                      .f = fit_evaluation,
                      .id = 'model',
                      predict_horizon = predict_horizon,
                      score_data = select(tst, time, status))
    
    
    scores %>% 
        mutate(resample_iteration = resample_iteration,
               ftr_selector = ftr_selector,
               n_predictors = n_predictors,
               .before = 1)
    
}

.rslurm_params <- expand.grid(
    resample_iteration = 1:250,
    ftr_selector = c('rsf','xgb','cph'),
    n_predictors = c(5, 10, 15, 20, 35, 50, 75),
    stringsAsFactors = FALSE
)

.rslurm_id <- as.numeric(Sys.getenv('SLURM_ARRAY_TASK_ID'))
.rslurm_istart <- .rslurm_id * 1 + 1
.rslurm_iend <- min((.rslurm_id + 1) * 1, nrow(.rslurm_params))

.rslurm_result <- do.call(
    what = parallel::mcmapply,
    args = c(
        FUN = .rslurm_func,
        .rslurm_params[.rslurm_istart:.rslurm_iend, , drop = FALSE],
        mc.cores = 1,
        mc.preschedule = TRUE,
        SIMPLIFY = FALSE
    )
)

saveRDS(
    .rslurm_result, 
    file = glue('results/output_{.rslurm_id}.RDS')
)
