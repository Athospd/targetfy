make_data <- function() data.frame(x = 1:40, y = (1:40) * 0.5 + sin(1:40))

fit_grid <- function(d, grid) lapply(grid, function(k) lm(y ~ poly(x, k), data = d))

pick_best <- function(grid, fits) grid[which.min(sapply(fits, AIC))]

next_grid <- function(best) c(best, best + 1, best + 2)

add_fitted <- function(d, fits, grid, best) {
  d$fitted <- fitted(fits[[which(grid == best)]])
  d
}
