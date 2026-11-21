rm(list = ls())
setwd("C:/a/folder/that/does/not/exist")
library(stats)
df <- read.csv("data/sales.csv")
df <- df[df$year > 2020, ]
df$rev <- log(df$rev)
model <- lm(rev ~ region, df)
print(summary(model))
model_summary <- summary(model)$coefficients
dir.create("out", showWarnings = FALSE)
write.csv(model_summary, "out/coefs.csv")
