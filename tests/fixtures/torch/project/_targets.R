library(targets)
library(tarchetypes)

tar_source()
tar_option_set(packages = "torch", memory = "transient")

torch_format <- tar_format(
  read = function(path) torch::torch_load(path),
  write = function(object, path) torch::torch_save(obj = object, path = path),
  marshal = function(object) {
    con <- rawConnection(raw(), open = "wr")
    on.exit(close(con))
    torch::torch_save(object, con)
    rawConnectionValue(con)
  },
  unmarshal = function(object) {
    con <- rawConnection(object, open = "r")
    on.exit(close(con))
    torch::torch_load(con)
  }
)

list(
  tar_target(points_file, "data/points.csv", format = "file"),
  tar_target(pts, read.csv(points_file)),
  tar_target(net, train_net(pts), format = torch_format),
  tar_target(pred, predict_net(net, pts))
)
