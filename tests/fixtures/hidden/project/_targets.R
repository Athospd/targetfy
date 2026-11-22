library(targets)
library(tarchetypes)
tar_source("R")
list(
  tar_file_read(sales_raw, "data/sales.csv", read = read.csv(!!.x)),
  tar_file_read(rates, "data/rates.csv", read = read.csv(!!.x)),
  tar_target(sales, add_tax(sales_raw, rates)),
  tar_target(total, total_revenue(sales))
)
