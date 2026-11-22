library(targets)
library(tarchetypes)
tar_source("R")
list(
  tar_file_read(sales, "data/sales.csv", read = read.csv(!!.x)),
  tar_target(total, total_revenue(sales)),
  tar_render(report_html, "report_targets.Rmd")
)
