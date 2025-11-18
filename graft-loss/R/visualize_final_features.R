##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title
##' @param final_features
##' @param phts_all
##' @param labels
visualize_final_features <- function(fig_prim_dx,
                                     fig_cpbypass,
                                     fig_txecmo,
                                     fig_hxsurg) {

  (fig_prim_dx + fig_cpbypass) /
    (fig_txecmo + fig_hxsurg)
  
    
}
