##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##'
##' @title

plot_pred_variable_smry <- function(data_gg, n_cats, colors, 
                                    lab_color = '',
                                    legend_position = c(0.2, .80),
                                    legend_direction = 'vertical') {

  
  bind_on <- data_gg %>% 
    filter(time <= 1) %>% 
    group_by(name) %>% 
    summarize(time = 1, 
              est = max(est), 
              ci_lwr = max(ci_lwr), 
              ci_upr = max(ci_upr))
  
  ggplot(bind_rows(data_gg, bind_on)) + 
    aes(x = time, y = est, 
        col = name, fill = name,
        ymin = ci_lwr, ymax = ci_upr) + 
    geom_line(size = 1) + 
    geom_ribbon(alpha = 0.1, linetype = 3) + 
    theme_bw() + 
    theme(panel.grid = element_blank(),
          legend.position = legend_position,
          legend.direction = legend_direction,
          text = element_text(size = 9),
          axis.text = element_text(size = 9),
          legend.text = element_text(size = 9),
          legend.key.size = unit(2/3, 'cm')) + 
    labs(y = 'Cumulative incidence of graft loss or mortality',
         x = 'Time since transplant, months',
         fill = lab_color, 
         color = lab_color) + 
    scale_y_continuous(labels = scales::percent, 
                       limits = c(0,1/2)) + 
    scale_x_continuous(breaks = seq(0, 1, length.out = 13),
                       labels = seq(0, 12),
                       limits = c(0, 1)) +
    coord_cartesian(xlim = c(0, 1)) +
    scale_color_manual(values = colors[1:n_cats]) + 
    scale_fill_manual(values = colors[1:n_cats])

}
