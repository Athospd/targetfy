region_totals <- function(sales) aggregate(amount ~ region, data = sales, FUN = sum)

params_by_region <- function(sales) {
  regions <- unique(sales$region)
  data.frame(region = regions, output_file = paste0("report_", regions, ".html"))
}

qmd_params_by_region <- function(sales) {
  regions <- unique(sales$region)
  data.frame(region = regions, output_file = paste0("qreport_", regions, ".html"))
}
