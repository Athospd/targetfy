library(targets)
library(tarchetypes)
tar_source("R")
list(
  tar_file_read(sales, "data/sales.csv", read = read.csv(!!.x)),
  tar_target(n, nrow(sales)),
  tar_target(avg, mean_price(sales)),
  tar_target(stop_here, avg * 2)
)
