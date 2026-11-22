add_revenue <- function(sales_raw) {
  sales_raw$revenue <- sales_raw$units * sales_raw$price
  sales_raw
}

fit_model <- function(sales_revenue) lm(revenue ~ units, data = sales_revenue)

add_predictions <- function(sales_revenue, model) {
  sales_revenue$predicted <- predict(model, sales_revenue)
  sales_revenue$residual <- sales_revenue$revenue - sales_revenue$predicted
  sales_revenue
}

newton_sqrt2 <- function(iterations) {
  x <- 1
  for (i in seq_len(iterations)) x <- x / 2 + 1 / x
  x
}

accumulate_units <- function(sales, limit) {
  total <- 0
  while (total < limit) total <- total + sum(sales$units)
  total
}

write_sales <- function(sales, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write.csv(sales, path, row.names = FALSE)
  path
}
