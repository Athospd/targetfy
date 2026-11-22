library(targets)

list(
  tar_target(cars_url, "https://raw.githubusercontent.com/tidyverse/readr/main/inst/extdata/mtcars.csv", format = "url"),
  tar_target(cars, read.csv(cars_url)),
  tar_target(mpg_by_cyl, aggregate(mpg ~ cyl, data = cars, FUN = mean))
)
