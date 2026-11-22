# Monthly sales trend per region, and a 3-month forecast.
setwd("~/work/regions")

files <- list.files("data/regions", pattern = "\\.csv$", full.names = TRUE)

fits <- list()
for (f in files) {
  region <- tools::file_path_sans_ext(basename(f))
  d <- read.csv(f)
  d$revenue <- d$units * d$price
  fits[[region]] <- lm(revenue ~ month, data = d)
}

trends <- data.frame(
  region = names(fits),
  slope = vapply(fits, function(m) unname(coef(m)[["month"]]), numeric(1)),
  r2 = vapply(fits, function(m) summary(m)$r.squared, numeric(1)),
  row.names = NULL
)
print(trends)

forecast <- do.call(rbind, lapply(names(fits), function(r) {
  data.frame(region = r, month = 13:15,
             revenue = unname(predict(fits[[r]], data.frame(month = 13:15))))
}))

dir.create("out", showWarnings = FALSE)
write.csv(trends, "out/trends.csv", row.names = FALSE)
write.csv(forecast, "out/forecast.csv", row.names = FALSE)
