find_r_script <- normalizePath(test_path("..", "..", "scripts", "find-r.R"),
                               winslash = "/")
find_env <- new.env()
sys.source(find_r_script, envir = find_env)

test_that("R's own startup variables are cleared for a child R, then restored", {
  before <- Sys.getenv(c("R_HOME", "R_LIBS_USER"))
  saved <- find_env$clean_r_env()
  expect_equal(Sys.getenv("R_HOME"), "")
  do.call(Sys.setenv, as.list(saved))
  expect_equal(Sys.getenv(c("R_HOME", "R_LIBS_USER")), before)
})

test_that("a library path the user set on purpose is kept", {
  old <- Sys.getenv("R_LIBS_USER", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("R_LIBS_USER")
          else Sys.setenv(R_LIBS_USER = old))
  Sys.setenv(R_LIBS_USER = "D:/my-r-libs")
  saved <- find_env$clean_r_env()
  do.call(Sys.setenv, as.list(saved))
  expect_equal(Sys.getenv("R_LIBS_USER"), "D:/my-r-libs")
})

test_that("each installation reports its own packages, and one is chosen", {
  res <- find_env$find_r()
  expect_true(length(res$installations) >= 1)
  expect_true(res$chosen %in% vapply(res$installations, `[[`, "", "rscript"))
  # This R runs the tests with targetfy's packages, so some R qualifies.
  expect_equal(res$status, "ok")
  # A package that exists nowhere is reported as not installed everywhere.
  pkg_probe <- find_env$probe(res$chosen, c("targets", "notapkgxyz"))
  expect_false(pkg_probe$works)
  expect_equal(pkg_probe$problems[[1]]$package, "notapkgxyz")
  expect_equal(pkg_probe$problems[[1]]$message, "not installed")
})
