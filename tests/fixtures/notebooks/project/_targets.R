library(targets)
library(tarchetypes)
tar_source("R")
list(
  tar_target(params, list(min_units = 10L)),
  tar_file_read(sales, "data/sales.csv", read = read.csv(!!.x)),
  tar_target(big, filter_big(sales, params$min_units)),
  tar_target(model, fit_price_model(big)),
  tar_target(coefs, coef(model))
)
