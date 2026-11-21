fixtures <- normalizePath(test_path("..", "fixtures"), winslash = "/")
check_script <- normalizePath(test_path("..", "..", "scripts", "check.R"),
                              winslash = "/")
check_env <- new.env()
sys.source(check_script, envir = check_env)

run_fixture <- function(name, scripts, ...) {
  dir <- file.path(fixtures, name)
  map <- jsonlite::read_json(file.path(dir, "map.json"), simplifyVector = FALSE)
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

test_that("an Unresolved Object makes the Script Sequence fail", {
  res <- run_fixture("unresolved", "script.R")
  expect_equal(res$status, "error")
  expect_match(res$errors[[1]], "model_data")
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

test_that("the command line returns JSON and the right exit code", {
  rscript <- file.path(R.home("bin"), "Rscript")
  dir <- file.path(fixtures, "sales_bug")
  out <- tempfile(fileext = ".json")
  code <- system2(rscript, c(shQuote(check_script),
                             "--project", shQuote(file.path(dir, "project")),
                             "--scripts", "analysis.R",
                             "--map", shQuote(file.path(dir, "map.json")),
                             "--out", shQuote(out)),
                  stdout = FALSE, stderr = FALSE)
  expect_equal(code, 1)
  expect_equal(jsonlite::read_json(out)$status, "not_equivalent")
})
