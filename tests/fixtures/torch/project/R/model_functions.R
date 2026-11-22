train_net <- function(pts) {
  torch::torch_manual_seed(1)
  net <- torch::nn_linear(1, 1)
  opt <- torch::optim_sgd(net$parameters, lr = 0.01)
  x <- torch::torch_tensor(as.matrix(pts["x"]), dtype = torch::torch_float())
  y <- torch::torch_tensor(as.matrix(pts["y"]), dtype = torch::torch_float())
  for (i in 1:200) {
    opt$zero_grad()
    loss <- torch::nnf_mse_loss(net(x), y)
    loss$backward()
    opt$step()
  }
  net
}

predict_net <- function(net, pts) as.numeric(net(torch::torch_tensor(as.matrix(pts["x"]), dtype = torch::torch_float())))
