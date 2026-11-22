cars <- read.csv("https://raw.githubusercontent.com/tidyverse/readr/main/inst/extdata/mtcars.csv")
mpg_by_cyl <- aggregate(mpg ~ cyl, data = cars, FUN = mean)
