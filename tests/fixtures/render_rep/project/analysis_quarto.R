sales <- read.csv("data/sales.csv")
totals <- aggregate(amount ~ region, data = sales, FUN = sum)
for (r in unique(sales$region)) {
  quarto::quarto_render("report.qmd", execute_params = list(region = r),
                        output_file = paste0("qreport_", r, ".html"), quiet = TRUE)
}
