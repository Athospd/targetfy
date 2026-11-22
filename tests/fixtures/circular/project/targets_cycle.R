library(targets)
library(tarchetypes)
tar_source("R")
list(
  tar_target(model, fit_model(sales)),
  tar_target(sales, add_predictions(sales, model))
)
