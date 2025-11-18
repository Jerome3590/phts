
library(tidyverse)
library(glue)

files <- list.files(path = "results", 
                    pattern = '^output',
                    full.names = TRUE)

output_cleaned <- map_dfr(files, read_rds)

write_rds(output_cleaned, 'mc_cv_results.rds')
