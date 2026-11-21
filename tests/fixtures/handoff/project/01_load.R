df <- data.frame(g = c("a", "b", "a"), v = c(1, 2, 3))
dir.create("tmp", showWarnings = FALSE)
saveRDS(df, "tmp/df.rds")
