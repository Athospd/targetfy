format_label <- function(coefs) {
  paste(names(coefs), round(coefs, 2), sep = "=", collapse = ", ")
}
