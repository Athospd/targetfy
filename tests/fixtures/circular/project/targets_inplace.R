library(targets)
library(tarchetypes)
tar_source("R")
list(
  tar_file_read(sales_raw, "data/sales.csv", read = read.csv(!!.x)),
  tar_target(sales_revenue, add_revenue(sales_raw)),
  tar_target(model, fit_model(sales_revenue)),
  tar_target(sales, add_predictions(sales_revenue, model)),
  tar_target(x, newton_sqrt2(20)),
  tar_target(total, accumulate_units(sales, 100)),
  tar_file(sales_csv, write_sales(sales, "data/sales.csv"))
)
