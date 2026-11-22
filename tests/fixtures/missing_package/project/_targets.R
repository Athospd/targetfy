library(targets)
library(notapkgxyz)
tar_source("R")
list(
  tar_target(x, make_x()),
  tar_target(y, total(x))
)
