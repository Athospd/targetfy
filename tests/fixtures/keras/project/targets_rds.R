library(targets)
library(tarchetypes)

tar_source()
tar_option_set(packages = "keras3", memory = "transient")

# keras3 needs a .keras extension; the store's path has none.
keras_format <- tar_format(
  read = function(path) {
    tmp <- paste0(tempfile(), ".keras")
    file.copy(path, tmp)
    keras3::load_model(tmp)
  },
  write = function(object, path) {
    tmp <- paste0(tempfile(), ".keras")
    keras3::save_model(object, tmp)
    file.rename(tmp, path)
  }
)

list(
  tar_target(points_file, "data/points.csv", format = "file"),
  tar_target(pts, read.csv(points_file)),
  tar_target(net, train_net(pts)),
  tar_target(pred, predict_net(net, pts))
)
