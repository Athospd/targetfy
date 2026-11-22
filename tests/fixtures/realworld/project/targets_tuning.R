library(targets)
library(tarchetypes)

tar_source("R_targets")

list(
  tar_target(d_raw, make_data()),
  tar_target(grid_step1, c(1, 2)),
  tar_target(fits_step1, fit_grid(d_raw, grid_step1)),
  tar_target(best_step1, pick_best(grid_step1, fits_step1)),
  tar_target(grid, next_grid(best_step1)),
  tar_target(fits, fit_grid(d_raw, grid)),
  tar_target(best, pick_best(grid, fits)),
  tar_target(d, add_fitted(d_raw, fits, grid, best))
)
