library(targets)
list(
  tar_target(a, 1:3),
  tar_target(b, a * 2),
  tar_target(y, model_data * b)
)
