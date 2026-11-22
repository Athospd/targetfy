make_data <- function() {
  d <- data.frame(g = rep(c("a", "b", "c"), each = 10), x = rep(1:10, 3))
  d$y <- d$x * rep(c(1, 2, 3), each = 10) + rep(c(0, 1, 2), each = 10)
  d
}

fit_poly <- function(d, deg) lm(y ~ poly(x, deg), data = d)

# One group's mean, named after its group, so the branches combine into the
# same named list as lapply(split(d, d$g), ...).
group_mean <- function(part) stats::setNames(list(mean(part$y)), part$g[[1]])

combine_named <- function(branches) do.call(c, unname(branches))
