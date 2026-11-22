library(stats)

summarise_groups <- function(d) aggregate(y ~ g, data = d, FUN = mean)
