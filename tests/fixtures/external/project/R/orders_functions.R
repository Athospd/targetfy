# The connection is opened inside each function, never a Target.
with_shop <- function(path, f) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con))
  f(con)
}

read_orders <- function(path) with_shop(path, function(con) DBI::dbGetQuery(con, "SELECT * FROM orders"))

# A cheap check: when it changes, the orders are read again.
orders_version <- function(path) with_shop(path, function(con)
  DBI::dbGetQuery(con, "SELECT COUNT(*) AS n, SUM(amount) AS total FROM orders"))

sum_by_region <- function(orders) aggregate(amount ~ region, data = orders, FUN = sum)
