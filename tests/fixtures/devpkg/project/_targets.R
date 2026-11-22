library(targets)
pkgload::load_all("devpkg", quiet = TRUE)
tar_option_set(imports = "demopkg")
list(tar_target(y, double_it(1:3)))
