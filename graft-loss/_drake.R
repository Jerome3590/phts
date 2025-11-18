## Load your packages, e.g. library(drake).
source("./scripts/packages.R")

## Load your R files
lapply(list.files("./R", full.names = TRUE), source)

## _drake.R must end with a call to drake_config().
## The arguments to drake_config() are basically the same as those to make().
drake_config(the_plan,
             lock_envir = FALSE,
             seed = 7302016, 
             prework = {
               
               set_flextable_defaults(theme_fun = "theme_box")
               
               rspec <- round_spec() %>%
                 round_using_magnitude(breaks = c(10, 100, Inf),
                                       digits = c(2, 1, 0))
               
               names(rspec) <- paste('table.glue', names(rspec), sep = '.')
               
               options(rspec)
               
             })
