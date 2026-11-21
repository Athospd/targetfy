library(targets)
library(tarchetypes)
tar_source("R_targets")
list(
  tar_file_read(sales, "data/sales.csv", read.csv(!!.x)),
  tar_target(sales_clean, clean_sales(sales)),
  tar_target(model, fit_model(sales_clean)),
  tar_target(model_summary, summarise_model(model)),
  tar_file(coefs_file, write_coefs(model_summary, "out/coefs.csv"))
)
