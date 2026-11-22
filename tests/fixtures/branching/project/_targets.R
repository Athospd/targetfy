library(targets)
library(tarchetypes)

tar_source("R")

list(
  tar_files_input(
    region_files,
    list.files("data/regions", pattern = "\\.csv$", full.names = TRUE)
  ),
  tar_target(
    region_fit,
    fit_region_trend(region_files),
    pattern = map(region_files),
    iteration = "list"
  ),
  tar_target(fits, combine_fits(region_fit)),
  tar_target(trends, summarise_trends(fits)),
  tar_target(
    forecast,
    forecast_revenue(region_fit),
    pattern = map(region_fit)
  ),
  tar_file(trends_csv, write_csv_file(trends, "out/trends.csv")),
  tar_file(forecast_csv, write_csv_file(forecast, "out/forecast.csv"))
)
