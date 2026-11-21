library(targets)
tar_source("R_targets")
list(
  tar_target(x, draw(100)),
  tar_target(m, mean(x))
)
