library(targets)
library(tarchetypes)

tar_source("R")
tar_option_set(packages = "dplyr")

degrees <- c(1, 2, 3)
fit_by_degree <- tar_map(
  values = list(deg = degrees),
  tar_target(fit, fit_poly(d, deg))
)

list(
  tar_target(d, make_data()),
  fit_by_degree,
  tar_combine(fits, fit_by_degree,
              command = stats::setNames(list(!!!.x), as.character(degrees))),
  tar_group_by(groups, d, g),
  tar_target(group_mean_branch, group_mean(groups), pattern = map(groups),
             iteration = "list"),
  tar_target(group_means, combine_named(group_mean_branch)),
  tar_rep(sims_reps, mean(rnorm(20)), batches = 4, reps = 25),
  tar_target(sims, unname(sims_reps))
)
