library(targets)
library(tarchetypes)

tar_source(c("R", "helpers.R", "utils"))
tar_option_set(packages = "stats", memory = "transient", garbage_collection = TRUE)

tar_hook_before(
  hook = options(contrasts = c("contr.sum", "contr.poly")),
  list(
    tar_target(d, make_data(42)),
    tar_target(fit, fit_model(d)),
    tar_target(coefs, coef(fit)),
    tar_target(summary_tbl, summarise_groups(d)),
    tar_target(label, label_coefs(coefs)),
    tar_target(extra, read_extra("absent.csv"), error = "null")
  )
)
