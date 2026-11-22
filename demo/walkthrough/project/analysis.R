# Sales analysis -------------------------------------------------------
library(readr)
library(dplyr)
library(ggplot2)

setwd("~/projects/sales")
dir.create("out", showWarnings = FALSE)

# Read and clean
sales <- read_csv("data/sales.csv", show_col_types = FALSE)
sales <- sales |>
  filter(year >= 2021) |>
  mutate(revenue = revenue / 1000)

head(sales)

# Revenue by region
by_region <- sales |>
  group_by(region) |>
  summarise(revenue = sum(revenue), .groups = "drop")

# Model
model <- lm(revenue ~ region + year, data = sales)
coefs <- broom::tidy(model)

# Outputs
plot <- ggplot(by_region, aes(region, revenue)) +
  geom_col(fill = "steelblue")
ggsave("out/revenue.png", plot, width = 6, height = 4)
write_csv(coefs, "out/coefs.csv")
