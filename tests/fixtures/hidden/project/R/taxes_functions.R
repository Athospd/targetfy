add_tax <- function(sales, rates) {
  sales$taxed <- sales$price * (1 + mean(rates$rate))
  sales
}

# The untracked version: reads the rates file itself, so the Pipeline
# never learns that it depends on it.
add_tax_untracked <- function(sales) add_tax(sales, read.csv("data/rates.csv"))

total_revenue <- function(sales) sum(sales$taxed * sales$units)
