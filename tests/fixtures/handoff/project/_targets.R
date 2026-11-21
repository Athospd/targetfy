library(targets)
library(tarchetypes)
tar_source("R_targets")
list(
  tar_target(raw, make_data()),
  tar_target(totals, total_by_group(raw)),
  tar_file(totals_file, write_totals(totals, "out/totals.csv"))
)
