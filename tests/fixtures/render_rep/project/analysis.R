sales <- read.csv("data/sales.csv")
totals <- aggregate(amount ~ region, data = sales, FUN = sum)
for (r in unique(sales$region)) {
  rmarkdown::render("report.Rmd", params = list(region = r),
                    output_file = paste0("report_", r, ".html"), quiet = TRUE)
}
