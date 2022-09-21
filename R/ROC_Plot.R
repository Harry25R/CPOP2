#' ROC_Plot
#'
#' @param roc_list A list of roc object from the pROC package
#'
#' @import dplyr
#' @import purrr
#' @import ggplot2
#' @export
#'
#' @examples
#' library(CPOP)
#' data(cpop_data_binary, package = 'CPOP')
#'
#' x1 = cpop_data_binary$x1
#' x2 = cpop_data_binary$x2
#' x3 = cpop_data_binary$x3
#' y1 = cpop_data_binary$y1
#' y2 = cpop_data_binary$y2
#' y3 = cpop_data_binary$y3
#'
#' set.seed(23)
#' x_list <- list(x1,x2)
#' y_list <- list(factor(y1), factor(y2))
#'
#' fCPOP_model <- Frankenstein_CPOP(x_list, y_list)
#' pred <- predict_cpop2(fCPOP_model$models, newx = x3)
#' roc_fCPOP <- roc(y3, pred)
#' ROC_Plot(list(roc_fCPOP))

ROC_Plot <- function(roc_list){
  data.labels <- roc_list %>%
    map(~tibble(AUC = .x$auc)) %>%
    bind_rows(.id = "name") %>%
    mutate(label_long=paste0(name," , AUC = ",paste(round(AUC,2))),
           label_AUC=paste0("AUC = ",paste(round(AUC,2))))

  ggroc(roc_list, size = 1.5) + theme_bw() + ggthemes::scale_color_tableau(name = "Model", labels=data.labels$label_long) +
    geom_segment(aes(x = 1, xend = 0, y = 0, yend = 1), color="grey50", linetype="dashed") +
    theme(legend.title=element_text(size=14)) + theme(legend.text = element_text(size = 12)) +
    ggtitle("")
}