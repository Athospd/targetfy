scale01 <- function(x) (x - min(x)) / (max(x) - min(x))

# set.seed() sat right before the only random draw, so it moves into the
# function and the value matches the script exactly.
make_data <- function(seed) {
  set.seed(seed)
  d <- data.frame(g = factor(rep(c("a", "b", "c"), each = 4)), x = 1:12)
  d$y <- d$x * 2 + as.integer(d$g) + rnorm(12, sd = 0.1)
  d$x01 <- scale01(d$x)
  d
}

fit_model <- function(d) lm(y ~ g + x01, data = d)

label_coefs <- function(coefs) tryCatch(format_label(coefs), error = function(e) "none")

read_extra <- function(path) read.csv(path)
