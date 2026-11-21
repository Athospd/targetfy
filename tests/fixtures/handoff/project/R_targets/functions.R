make_data <- function() data.frame(g = c("a", "b", "a"), v = c(1, 2, 3))
total_by_group <- function(raw) aggregate(v ~ g, raw, sum)
write_totals <- function(totals, path) {
  dir.create(dirname(path), showWarnings = FALSE)
  write.csv(totals, path, row.names = FALSE)
  path
}
