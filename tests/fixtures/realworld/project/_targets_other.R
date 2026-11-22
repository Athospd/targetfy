library(targets)
tar_option_set(packages = "stats")
tar_source()
list(tar_target(other_value, existing_value() * 2))
