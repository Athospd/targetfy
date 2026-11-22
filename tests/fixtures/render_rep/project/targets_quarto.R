library(targets)
library(tarchetypes)

tar_source()

list(
  tar_target(sales_file, "data/sales.csv", format = "file"),
  tar_target(sales, read.csv(sales_file)),
  tar_target(totals, region_totals(sales)),
  tar_quarto_rep(report, "report_targets.qmd",
                 execute_params = qmd_params_by_region(sales), quiet = TRUE)
)
