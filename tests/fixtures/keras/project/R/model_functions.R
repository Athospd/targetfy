train_net <- function(pts) {
  keras3::set_random_seed(1)
  net <- keras3::keras_model_sequential(input_shape = 1) |> keras3::layer_dense(units = 1)
  net |> keras3::compile(optimizer = keras3::optimizer_sgd(learning_rate = 0.01), loss = "mse")
  net |> keras3::fit(as.matrix(pts["x"]), as.matrix(pts["y"]), epochs = 50, verbose = 0)
  net
}

predict_net <- function(net, pts) as.numeric(predict(net, as.matrix(pts["x"]), verbose = 0))
