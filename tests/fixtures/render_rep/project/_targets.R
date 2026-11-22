library(targets)
library(tarchetypes)

tar_source()

list(
  tar_target(sales_file, "data/sales.csv", format = "file"),
  tar_target(sales, read.csv(sales_file)),
  tar_target(totals, region_totals(sales)),
  tar_render_rep(report, "report_targets.Rmd", params = params_by_region(sales), quiet = TRUE)
)
