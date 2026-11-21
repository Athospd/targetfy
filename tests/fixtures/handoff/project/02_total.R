df <- readRDS("tmp/df.rds")
totals <- aggregate(v ~ g, df, sum)
dir.create("out", showWarnings = FALSE)
write.csv(totals, "out/totals.csv", row.names = FALSE)
