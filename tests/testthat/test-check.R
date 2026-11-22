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

# --- v2: circular references -------------------------------------------------

run_pipeline <- function(name, scripts, pipeline, ...) {
  project <- file.path(fixtures, name, "project")
  map <- jsonlite::read_json(file.path(project, check_env$map_for(pipeline)),
                             simplifyVector = FALSE)
  check_env$targetfy_check(project, scripts, map, pipeline = pipeline, ...)
}

finding <- function(scan, kind) Filter(function(f) f$kind == kind, scan$findings)

test_that("the flow scan finds versions, in-place files and carried loops", {
  scan <- check_env$flow_scan(file.path(fixtures, "circular", "project"), "clean.R")
  re <- finding(scan, "reassigned")
  expect_length(re, 1)
  expect_equal(re[[1]]$name, "sales")
  expect_equal(re[[1]]$used_at, "clean.R:3")
  expect_equal(re[[1]]$changed_at, "clean.R:4")
  expect_true(re[[1]]$cycle)
  inplace <- finding(scan, "in_place_file")
  expect_equal(inplace[[1]]$path, "data/sales.csv")
  carried <- finding(scan, "carried_loop")
  expect_setequal(vapply(carried, function(f) f$loop, ""), c("for", "while"))
  expect_length(finding(scan, "branch_candidate"), 0)
})

test_that("independent loops, applies and global state are told apart", {
  dir <- tempfile(); dir.create(dir)
  writeLines(c(
    "files <- c('a.csv', 'b.csv')",
    "fits <- list()",
    "for (f in files) fits[[f]] <- nchar(f)",
    "out <- c()",
    "for (i in 1:3) out <- c(out, i * 2)",
    "sq <- lapply(1:3, function(i) i^2)",
    "acc <- Reduce(`+`, 1:5, accumulate = TRUE)",
    "options(digits = 3)",
    "set.seed(1)",
    "counter <- 0",
    "bump <- function() counter <<- counter + 1",
    "y <- later + 1",
    "later <- 2",
    "x <- 1; y2 <- x; x <- 5",
    "saveRDS(y2, 'tmp/y2.rds')",
    "y3 <- readRDS('tmp/y2.rds')"), file.path(dir, "s.R"))
  scan <- check_env$flow_scan(dir, "s.R")
  branch <- finding(scan, "branch_candidate")
  expect_equal(vapply(branch, function(f) f$where, ""), c("s.R:3", "s.R:5", "s.R:6"))
  expect_equal(as.character(unlist(branch[[1]]$collects)), "fits")
  expect_equal(finding(scan, "carried_loop")[[1]]$where, "s.R:7")
  flags <- vapply(finding(scan, "global_state"), function(f) f$flag, "")
  expect_true("global_assign" %in% flags)
  setups <- vapply(finding(scan, "pipeline_setup"), function(f) f$setup, "")
  expect_true(all(c("global_options", "seed") %in% setups))
  expect_equal(finding(scan, "defined_later")[[1]]$name, "later")
  re <- finding(scan, "reassigned")
  expect_equal(re[[1]]$name, "x")
  expect_false(re[[1]]$cycle)
  expect_equal(finding(scan, "handoff")[[1]]$path, "tmp/y2.rds")
})

test_that("a versioned Conversion with a redirected file is equivalent", {
  res <- run_pipeline("circular", "clean.R", "_targets.R")
  expect_equal(res$status, "equivalent")
  expect_equal(target_result(res, "sales")$result, "match")
  expect_equal(target_result(res, "x")$result, "match")
  expect_equal(target_result(res, "total")$result, "match")
  expect_equal(res$files[[1]]$file, "data/sales.csv")
  expect_equal(res$files[[1]]$redirected_to, "data/sales_targetfy.csv")
  expect_equal(res$files[[1]]$result, "match")
  expect_length(res$outdated_after_build, 0)
})

test_that("a Pipeline that overwrites its own input is caught", {
  res <- run_pipeline("circular", "clean.R", "targets_inplace.R")
  expect_equal(res$status, "not_equivalent")
  expect_true("sales_raw_file" %in% unlist(res$outdated_after_build))
  expect_match(res$errors[[1]], "out of date right after it was built")
})

test_that("a Pipeline whose graph has a cycle fails with a hint", {
  res <- run_pipeline("circular", "clean.R", "targets_cycle.R")
  expect_equal(res$status, "not_equivalent")
  expect_match(res$errors[[1]], "has a cycle")
})

# --- v2: notebooks -------------------------------------------------------------

nb_dir <- file.path(fixtures, "notebooks", "project")

test_that("a .qmd keeps R chunks, drops eval: false, display and other languages", {
  t <- check_env$tangle(file.path(nb_dir, "analysis", "report.qmd"))
  expect_true(t$notebook)
  expect_equal(t$code[[1]], "params <- list(min_units = 10L)")
  expect_false(any(grepl("never runs|not R|display_only", t$code)))
  expect_true(any(grepl("lm(price ~ units", t$code, fixed = TRUE)))
  expect_equal(check_env$origin_label("analysis/report.qmd", t,
                                      which(grepl("^model <-", t$code))),
               "analysis/report.qmd:31")
  reasons <- vapply(t$skipped, function(s) s$reason, "")
  expect_true(any(grepl("eval = FALSE", reasons)))
  expect_true(any(grepl("python", reasons)))
  expect_equal(t$inline[[1]]$code, "nrow(big)")
})

test_that(".Rmd, .md and .ipynb code is extracted with its origin", {
  rmd <- check_env$tangle(file.path(nb_dir, "report.Rmd"))
  expect_false(any(grepl("skipped", rmd$code)))
  expect_equal(rmd$inline[[1]]$code, "sum(sales$units * sales$price)")
  md <- check_env$tangle(file.path(nb_dir, "notes.md"))
  expect_equal(md$code, c('sales <- read.csv("data/sales.csv")',
                          "avg <- mean(sales$price)"))
  nb <- check_env$tangle(file.path(nb_dir, "nb.ipynb"))
  expect_equal(check_env$origin_label("nb.ipynb", nb, 3), "nb.ipynb:cell 3, line 1")
  expect_error(check_env$tangle(file.path(nb_dir, "py.ipynb")), "python kernel")
})

test_that("a .qmd runs from its own folder and its Conversion is equivalent", {
  res <- run_pipeline("notebooks", "analysis/report.qmd", "_targets.R")
  expect_equal(res$status, "equivalent")
  expect_equal(target_result(res, "params")$result, "match")
  expect_equal(target_result(res, "coefs")$result, "match")
})

test_that("an R-kernel .ipynb Conversion is equivalent", {
  res <- run_pipeline("notebooks", "nb.ipynb", "targets_nb.R")
  expect_equal(res$status, "equivalent")
  expect_equal(target_result(res, "stop_here")$result, "match")
})

test_that("a notebook failure is reported at its notebook line", {
  dir <- tempfile(); dir.create(dir)
  writeLines(c("# t", "", "```{r}", "x <- 1", "stop('boom')", "```"),
             file.path(dir, "f.qmd"))
  writeLines(c("library(targets)", "list(tar_target(x, 1))"),
             file.path(dir, "_targets.R"))
  res <- check_env$targetfy_check(dir, "f.qmd", list(targets = list(x = "x")))
  expect_equal(res$script_failure$line, 5)
  expect_equal(res$script_failure$where, "f.qmd:5")
})

test_that("packages are read from notebook chunks", {
  f <- tempfile(fileext = ".Rmd")
  writeLines(c("```{r}", "library(dplyr)", "```", "```r", "library(nope)", "```"), f)
  expect_equal(check_env$required_packages(f), "dplyr")
})

# --- v2: dynamic branching -----------------------------------------------------

test_that("the region loop is a branch candidate, and its branched Pipeline is equivalent", {
  project <- file.path(fixtures, "branching", "project")
  scan <- check_env$flow_scan(project, "regional_trends.R")
  loop <- Filter(function(f) f$kind == "branch_candidate" && grepl(":7$", f$where),
                 scan$findings)
  expect_length(loop, 1)
  expect_equal(as.character(unlist(loop[[1]]$collects)), "fits")
  expect_length(finding(scan, "carried_loop"), 0)
  res <- run_fixture("branching", "regional_trends.R")
  expect_equal(res$status, "equivalent")
  expect_equal(target_result(res, "region_fit")$result, "not_compared")
  expect_equal(target_result(res, "fits")$result, "match")
  expect_equal(target_result(res, "forecast")$result, "match")
  expect_true(all(vapply(res$files, function(f) f$result == "match", TRUE)))
})

test_that("the render Enhancement builds the document from the Pipeline", {
  skip_if_not(rmarkdown::pandoc_available(), "pandoc is not available")
  res <- run_pipeline("notebooks", "report.Rmd", "targets_report.R")
  expect_equal(res$status, "equivalent")
  expect_equal(target_result(res, "total")$result, "match")
  expect_equal(target_result(res, "report_html")$result, "not_compared")
  expect_length(res$outdated_after_build, 0)
})

# --- v2: Pipeline setup (tar_source(), tar_option_set()) -----------------------

setup_dir <- file.path(fixtures, "setup", "project")

setup_finding <- function(scan, setup) {
  Filter(function(f) identical(f$setup, setup), scan$findings)
}

test_that("the scan finds what belongs in tar_source() and tar_option_set()", {
  scan <- check_env$flow_scan(setup_dir, "analysis.R")
  src <- finding(scan, "sourced_file")[[1]]
  expect_equal(src$path, "helpers.R")
  expect_true(src$functions_only)
  expect_equal(as.character(unlist(src$functions)), "summarise_groups")
  folder <- finding(scan, "sourced_folder")[[1]]
  expect_equal(folder$path, "utils")
  expect_length(unlist(folder$files_with_work), 0)
  expect_length(finding(scan, "branch_candidate"), 0)
  expect_equal(finding(scan, "script_function")[[1]]$name, "scale01")
  expect_match(setup_finding(scan, "global_options")[[1]]$code, "contrasts")
  expect_equal(setup_finding(scan, "seed")[[1]]$suggest, "tar_option_set(seed = 42)")
  expect_length(setup_finding(scan, "memory"), 2)
  expect_equal(setup_finding(scan, "tolerated_error")[[1]]$where, "analysis.R:22")
})

test_that("sourced files with work, library setup and load_all are told apart", {
  dir <- tempfile(); dir.create(dir)
  writeLines(c("helper <- function(x) x", "cfg <- read.csv('cfg.csv')"),
             file.path(dir, "setup.R"))
  writeLines(c("source('setup.R')", ".libPaths('C:/lib')", "renv::activate()",
               "source('renv/activate.R')", "pkgload::load_all('mypkg')"),
             file.path(dir, "s.R"))
  scan <- check_env$flow_scan(dir, "s.R")
  src <- finding(scan, "sourced_file")[[1]]
  expect_false(src$functions_only)
  expect_equal(as.numeric(unlist(src$work_lines)), 2)
  expect_match(src$message, "setup_functions.R")
  expect_length(setup_finding(scan, "environment_setup"), 3)
  expect_equal(setup_finding(scan, "dev_package")[[1]]$path, "mypkg")
})

test_that("options kept in the Pipeline script or a hook keep it equivalent", {
  res <- run_pipeline("setup", "analysis.R", "_targets.R")
  expect_equal(res$status, "equivalent")
  d <- target_result(res, "d")
  expect_true(d$stochastic)
  expect_equal(d$result, "match")   # set.seed() moved into the function
  expect_equal(res$tolerated_errors[[1]]$target, "extra")
  expect_length(res$outdated_after_build, 0)
  expect_equal(run_pipeline("setup", "analysis.R", "targets_hook.R")$status, "equivalent")
})

test_that("dropping options() the script relies on is caught", {
  res <- run_pipeline("setup", "analysis.R", "targets_nooptions.R")
  expect_equal(res$status, "not_equivalent")
  expect_equal(target_result(res, "coefs")$result, "mismatch")
})

test_that("a load_all() package with imports = is equivalent", {
  skip_if_not_installed("pkgload")
  res <- run_fixture("devpkg", "script.R")
  expect_equal(res$status, "equivalent")
  expect_equal(target_result(res, "y")$result, "match")
})
