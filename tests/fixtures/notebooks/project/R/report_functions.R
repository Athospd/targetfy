filter_big <- function(sales, min_units) sales[sales$units >= min_units, ]

fit_price_model <- function(big) lm(price ~ units, data = big)

total_revenue <- function(sales) sum(sales$units * sales$price)
