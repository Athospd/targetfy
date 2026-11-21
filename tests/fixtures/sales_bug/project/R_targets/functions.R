clean_sales <- function(sales) {
  sales <- sales[sales$year >= 2020, ]
  sales$rev <- log(sales$rev)
  sales
}

fit_model <- function(sales_clean) lm(rev ~ region, sales_clean)

summarise_model <- function(model) summary(model)$coefficients

write_coefs <- function(model_summary, path) {
  dir.create(dirname(path), showWarnings = FALSE)
  write.csv(model_summary, path)
  path
}
