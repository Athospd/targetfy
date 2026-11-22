library(stats)
source("helpers.R")
invisible(lapply(list.files("utils", full.names = TRUE), source))
options(contrasts = c("contr.sum", "contr.poly"))
set.seed(42)

scale01 <- function(x) (x - min(x)) / (max(x) - min(x))

d <- data.frame(g = factor(rep(c("a", "b", "c"), each = 4)), x = 1:12)
d$y <- d$x * 2 + as.integer(d$g) + rnorm(12, sd = 0.1)
d$x01 <- scale01(d$x)

fit <- lm(y ~ g + x01, data = d)
coefs <- coef(fit)

big <- matrix(0, 500, 500)
rm(big)
gc()

summary_tbl <- summarise_groups(d)
label <- tryCatch(format_label(coefs), error = function(e) "none")
try(extra <- read.csv("absent.csv"))
