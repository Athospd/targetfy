d <- data.frame(g = rep(c("a", "b", "c"), each = 10), x = rep(1:10, 3))
d$y <- d$x * rep(c(1, 2, 3), each = 10) + rep(c(0, 1, 2), each = 10)

fits <- list()
for (deg in c(1, 2, 3)) {
  fits[[as.character(deg)]] <- lm(y ~ poly(x, deg), data = d)
}

group_means <- lapply(split(d, d$g), function(part) mean(part$y))

sims <- replicate(100, mean(rnorm(20)))
