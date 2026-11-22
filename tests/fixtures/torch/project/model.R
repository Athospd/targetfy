library(torch)
pts <- read.csv("data/points.csv")
torch_manual_seed(1)
net <- nn_linear(1, 1)
opt <- optim_sgd(net$parameters, lr = 0.01)
x <- torch_tensor(as.matrix(pts["x"]), dtype = torch_float())
y <- torch_tensor(as.matrix(pts["y"]), dtype = torch_float())
for (i in 1:200) {
  opt$zero_grad()
  loss <- nnf_mse_loss(net(x), y)
  loss$backward()
  opt$step()
}
pred <- as.numeric(net(x))
