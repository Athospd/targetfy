# One region's trend, named after its file, so the branches combine into
# the same named list the script's loop builds.
fit_region_trend <- function(region_file) {
  region <- tools::file_path_sans_ext(basename(region_file))
  d <- read.csv(region_file)
  d$revenue <- d$units * d$price
  stats::setNames(list(lm(revenue ~ month, data = d)), region)
}

# Branch values come back named after the branches (region_fit_3f2a...):
# drop those names and keep the regions'.
combine_fits <- function(region_fit) do.call(c, unname(region_fit))

summarise_trends <- function(fits) {
  data.frame(
    region = names(fits),
    slope = vapply(fits, function(m) unname(coef(m)[["month"]]), numeric(1)),
    r2 = vapply(fits, function(m) summary(m)$r.squared, numeric(1)),
    row.names = NULL
  )
}

forecast_revenue <- function(fits) {
  do.call(rbind, lapply(names(fits), function(r) {
    data.frame(region = r, month = 13:15,
               revenue = unname(predict(fits[[r]], data.frame(month = 13:15))))
  }))
}

write_csv_file <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write.csv(x, path, row.names = FALSE)
  path
}
