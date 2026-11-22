library(targets)
library(tarchetypes)

tar_source()
tar_option_set(packages = "DBI")

list(
  tar_target(orders, read_orders("data/shop.sqlite")),
  tar_target(by_region, sum_by_region(orders))
)
