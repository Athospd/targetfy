sales <- read.csv("data/sales.csv")
rates_file <- "data/rates.csv"
rates <- read.csv(rates_file)
sales$taxed <- sales$price * (1 + mean(rates$rate))
total <- sum(sales$taxed * sales$units)
run_date <- Sys.Date()
