fixtures <- normalizePath(test_path("..", "fixtures"), winslash = "/")
check_script <- normalizePath(test_path("..", "..", "scripts", "check.R"),
                              winslash = "/")
check_env <- new.env()
sys.source(check_script, envir = check_env)

run_fixture <- function(name, scripts, ...) {
  dir <- file.path(fixtures, name)
  map <- jsonlite::read_json(file.path(dir, "project", "targetfy-map.json"),
                             simplifyVector = FALSE)
  check_env$targetfy_check(file.path(dir, "project"), scripts, map, ...)
}

target_result <- function(res, name) {
  Filter(function(t) t$target == name, res$targets)[[1]]
}

test_that("an equivalent Conversion passes, model calls and setwd included", {
  res <- run_fixture("sales", "analysis.R")
  expect_equal(res$status, "equivalent")
  expect_equal(target_result(res, "model")$result, "match")
  expect_equal(target_result(res, "sales")$result, "not_compared")
  expect_equal(res$files[[1]]$result, "match")
})

test_that("the source project is never modified", {
  project <- file.path(fixtures, "sales", "project")
  before <- check_env$file_hashes(project)
  run_fixture("sales", "analysis.R")
  expect_identical(check_env$file_hashes(project), before)
  expect_false(dir.exists(file.path(project, "_targets")))
  expect_false(dir.exists(file.path(project, "out")))
})

test_that("a wrong filter is caught as a mismatch", {
  res <- run_fixture("sales_bug", "analysis.R")
  expect_equal(res$status, "not_equivalent")
  clean <- target_result(res, "sales_clean")
  expect_equal(clean$result, "mismatch")
  expect_false(clean$stochastic)
  expect_equal(res$files[[1]]$result, "mismatch")
})

test_that("visible random calls make Targets stochastic, compared by structure", {
  res <- run_fixture("stochastic", "simulate.R")
  expect_equal(res$status, "equivalent")
  x <- target_result(res, "x")
  expect_true(x$stochastic)
  expect_match(x$stochastic_reason, "rnorm")
  expect_equal(x$result, "structure_match")
  m <- target_result(res, "m")
  expect_equal(m$stochastic_reason, "value changes with the seed")
})

test_that("hidden randomness is found by rebuilding with a new seed", {
  res <- run_fixture("stochastic_hidden", "simulate.R")
  x <- target_result(res, "x")
  expect_equal(x$stochastic_reason, "value changes with the seed")
  expect_equal(x$result, "structure_match")
  expect_equal(res$status, "equivalent")
})

test_that("Handoff Files are excluded and Script Sequences run in order", {
  res <- run_fixture("handoff", c("01_load.R", "02_total.R"))
  expect_equal(res$status, "equivalent")
  results <- setNames(vapply(res$files, `[[`, "", "result"),
                      vapply(res$files, `[[`, "", "file"))
  expect_equal(results[["tmp/df.rds"]], "handoff")
  expect_equal(results[["out/totals.csv"]], "match")
})

test_that("scripts that fail on their own fall back to the Static Check", {
  res <- run_fixture("unresolved", "script.R")
  expect_equal(res$status, "static_pass")
  expect_equal(res$equivalence, "unverified")
  expect_equal(res$script_failure$script, "script.R")
  expect_equal(res$script_failure$line, 3)
  expect_match(res$script_failure$message, "model_data")
  after <- vapply(res$targets, `[[`, NA, "after_failure")
  names(after) <- vapply(res$targets, `[[`, "", "target")
  expect_equal(after[c("a", "b", "y")], c(a = FALSE, b = FALSE, y = TRUE))
})

test_that("static mode never runs anything and marks Equivalence unverified", {
  res <- run_fixture("sales", "analysis.R", mode = "static")
  expect_equal(res$status, "static_pass")
  expect_equal(res$equivalence, "unverified")
  expect_length(res$targets, 0)
})

test_that("a Pipeline that does not parse fails the Static Check", {
  res <- run_fixture("broken", "script.R", mode = "static")
  expect_equal(res$status, "static_fail")
  expect_named(res$static$parse_errors, "_targets.R")
})

test_that("a copy over the size limit asks for confirmation", {
  res <- run_fixture("sales", "analysis.R", max_copy_mb = 0)
  expect_equal(res$status, "needs_confirmation")
})

test_that("a missing Source Script is an error", {
  res <- run_fixture("sales", "nope.R")
  expect_equal(res$status, "error")
})

test_that("the command line reads the Step Map from the project by default", {
  rscript <- file.path(R.home("bin"), "Rscript")
  dir <- file.path(fixtures, "sales_bug")
  out <- tempfile(fileext = ".json")
  code <- system2(rscript, c(shQuote(check_script),
                             "--project", shQuote(file.path(dir, "project")),
                             "--scripts", "analysis.R",
                             "--out", shQuote(out)),
                  stdout = FALSE, stderr = FALSE)
  expect_equal(code, 1)
  expect_equal(jsonlite::read_json(out)$status, "not_equivalent")
})

test_that("an existing _targets.R is left alone when targets_<name>.R is checked", {
  dir <- file.path(fixtures, "existing_pipeline")
  project <- file.path(dir, "project")
  before <- check_env$file_hashes(project)
  map <- jsonlite::read_json(file.path(project, "targetfy-map_analysis.json"),
                             simplifyVector = FALSE)
  res <- check_env$targetfy_check(project, "analysis.R", map,
                                  pipeline = "targets_analysis.R")
  expect_equal(res$status, "equivalent")
  expect_equal(res$store, "_targets_analysis")
  expect_identical(check_env$file_hashes(project), before)
})

test_that("the command line finds targetfy-map_<name>.json for targets_<name>.R", {
  rscript <- file.path(R.home("bin"), "Rscript")
  project <- file.path(fixtures, "existing_pipeline", "project")
  out <- tempfile(fileext = ".json")
  code <- system2(rscript, c(shQuote(check_script),
                             "--project", shQuote(project),
                             "--scripts", "analysis.R",
                             "--pipeline", "targets_analysis.R",
                             "--out", shQuote(out)),
                  stdout = FALSE, stderr = FALSE)
  expect_equal(code, 0)
  res <- jsonlite::read_json(out)
  expect_equal(res$status, "equivalent")
  expect_true(any(vapply(res$targets, function(t) t$result == "match", TRUE)))
})

test_that("a missing package is reported as not checked, never as a bug", {
  res <- run_fixture("missing_package", "script.R")
  expect_equal(res$status, "not_checked")
  expect_equal(res$equivalence, "unverified")
  expect_equal(as.character(res$missing_packages), "notapkgxyz")
  expect_equal(check_env$EXIT_CODES[["not_checked"]], 0)
  res <- run_fixture("missing_package", "script.R", mode = "static")
  expect_equal(res$status, "not_checked")
})

test_that("required packages are read from library, :: and tar_option_set", {
  f <- tempfile(fileext = ".R")
  writeLines(c("library(dplyr)", "require('tidyr')",
               "x <- purrr::map(1, identity)",
               "library(p, character.only = TRUE)",
               "targets::tar_option_set(packages = c('readr', 'fs'))"), f)
  expect_equal(check_env$required_packages(f),
               c("dplyr", "fs", "purrr", "readr", "targets", "tidyr"))
})

test_that("parsnip engines count as required packages", {
  f <- tempfile(fileext = ".R")
  writeLines(c("m <- logistic_reg() %>% set_engine('glmnet')",
               "t <- set_engine(decision_tree(), 'rpart')",
               "l <- linear_reg() %>% set_engine('lm')",
               "b <- boost_tree() %>% set_engine('lightgbm')"), f)
  expect_equal(check_env$required_packages(f),
               c("bonsai", "glmnet", "lightgbm", "rpart"))
})
