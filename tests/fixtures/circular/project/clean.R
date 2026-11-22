sales <- read.csv("data/sales.csv")
sales$revenue <- sales$units * sales$price
model <- lm(revenue ~ units, data = sales)
sales$predicted <- predict(model, sales)
sales$residual <- sales$revenue - sales$predicted

# Newton's method for sqrt(2): each iteration feeds the next.
x <- 1
for (i in 1:20) x <- x / 2 + 1 / x
total <- 0
while (total < 100) total <- total + sum(sales$units)

write.csv(sales, "data/sales.csv", row.names = FALSE)
