library(targets)
library(tarchetypes)
tar_source("R")
list(
  tar_file_read(sales_raw, "data/sales.csv", read = read.csv(!!.x)),
  tar_target(sales, add_tax_untracked(sales_raw)),
  tar_target(total, total_revenue(sales))
)
