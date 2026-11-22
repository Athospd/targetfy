library(targets)
library(tarchetypes)

tar_source()
tar_option_set(packages = "DBI")

list(
  tar_change(orders, read_orders("data/shop.sqlite"),
             change = orders_version("data/shop.sqlite")),
  tar_target(by_region, sum_by_region(orders))
)
