# targetfy check: decides whether a Conversion is accepted (see docs/adr/0001).
#
# Usage:
#   Rscript check.R --project DIR --scripts a.R[,b.R...]
#                   [--map map.json]   (default: DIR/targetfy-map.json)
#                   [--mode equivalence|static] [--max-copy-mb 1024]
#                   [--allow-large] [--keep] [--out result.json]
#
# Never touches DIR: every run happens in throwaway copies.
#
# Exit codes: 0 equivalent / static_pass, 1 not_equivalent / static_fail,
#             2 error, 3 needs_confirmation (copy too large).

`%||%` <- function(a, b) if (is.null(a)) b else a

RANDOM_FUNS <- c(
  "set.seed", "sample", "sample.int", "runif", "rnorm", "rbinom", "rpois",
  "rexp", "rgamma", "rbeta", "rt", "rchisq", "rmultinom", "rlnorm",
  "rweibull", "rcauchy", "rgeom", "rhyper", "rnbinom", "rlogis", "rf",
  "slice_sample", "sample_n", "sample_frac", "initial_split", "vfold_cv",
  "bootstraps", "createDataPartition", "randomForest", "ranger", "kmeans",
  "xgb.train", "xgboost", "lgb.train", "lightgbm", "cv.glmnet"
)

# Files whose bytes embed timestamps/metadata: compared by existence only.
LOOSE_FILE_EXT <- c("pdf", "png", "jpg", "jpeg", "svg", "tif", "tiff",
                    "xlsx", "xls", "docx", "pptx", "html", "rds", "rdata")

COPY_EXCLUDE <- c("^\\.git/", "^_targets/", "^_targets_reseed/",
                  "^\\.Rproj\\.user/", "^renv/library/", "^renv/staging/")

# ---------------------------------------------------------------------------
# Project copies
# ---------------------------------------------------------------------------

project_files <- function(dir) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  keep <- !Reduce(`|`, lapply(COPY_EXCLUDE, grepl, x = files), FALSE)
  files[keep]
}

copy_project <- function(from, to, files) {
  dir.create(to, recursive = TRUE, showWarnings = FALSE)
  for (f in files) {
    dest <- file.path(to, f)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.copy(file.path(from, f), dest, copy.date = TRUE)
  }
  invisible(to)
}

file_hashes <- function(dir) {
  files <- project_files(dir)
  stats::setNames(unname(tools::md5sum(file.path(dir, files))), files)
}

written_files <- function(before, after) {
  new <- setdiff(names(after), names(before))
  common <- intersect(names(after), names(before))
  changed <- common[after[common] != before[common]]
  sort(c(new, changed))
}

# ---------------------------------------------------------------------------
# Running the Script Sequence
# ---------------------------------------------------------------------------

# Runs in a fresh R session with the copy as working directory. Stubs are
# attached (not put in globalenv) so rm(list = ls()) can't remove them; they
# keep the script inside its copy and stop it installing anything.
run_scripts_session <- function(wd, scripts, names, out) {
  setwd(wd)
  stubs <- new.env()
  stubs$setwd <- function(dir) invisible(getwd())
  stubs$install.packages <- function(...) invisible(NULL)
  stubs$View <- function(...) invisible(NULL)
  attach(stubs, name = "targetfy_stubs", warn.conflicts = FALSE)
  err <- NULL
  tryCatch(
    for (s in scripts) sys.source(s, envir = globalenv(), keep.source = FALSE),
    error = function(e) err <<- conditionMessage(e)
  )
  present <- names[vapply(names, exists, logical(1), envir = globalenv(),
                          inherits = FALSE)]
  saveRDS(mget(present, envir = globalenv()), out)
  list(error = err, present = present)
}

run_scripts <- function(wd, scripts, names, out) {
  callr::r(run_scripts_session, args = list(wd, scripts, names, out))
}

# ---------------------------------------------------------------------------
# Running the Pipeline
# ---------------------------------------------------------------------------

with_wd <- function(dir, code) {
  old <- setwd(dir)
  on.exit(setwd(old))
  force(code)
}

static_check <- function(wd) {
  out <- list(parse_errors = list(), validate = NULL, manifest = NULL)
  r_files <- list.files(wd, pattern = "\\.[Rr]$", recursive = TRUE)
  for (f in r_files) {
    msg <- tryCatch({ parse(file.path(wd, f)); NULL },
                    error = function(e) conditionMessage(e))
    if (!is.null(msg)) out$parse_errors[[f]] <- msg
  }
  if (!file.exists(file.path(wd, "_targets.R"))) {
    out$validate <- "_targets.R not found"
    return(out)
  }
  with_wd(wd, {
    out$validate <- tryCatch({ targets::tar_validate(); "ok" },
                             error = function(e) conditionMessage(e))
    out$manifest <- tryCatch(
      as.data.frame(targets::tar_manifest(fields = c("name", "command"))),
      error = function(e) conditionMessage(e)
    )
  })
  out
}

static_ok <- function(s) {
  length(s$parse_errors) == 0 && identical(s$validate, "ok") &&
    is.data.frame(s$manifest)
}

build_pipeline <- function(wd, script = "_targets.R", store = "_targets",
                           names = NULL) {
  with_wd(wd, tryCatch({
    targets::tar_make(names = !!names, script = script, store = store,
                      reporter = "silent")
    errored <- targets::tar_meta(fields = error, store = store,
                                 complete_only = TRUE)
    if (nrow(errored)) {
      paste0(errored$name, ": ", errored$error, collapse = "; ")
    } else NULL
  }, error = function(e) conditionMessage(e)))
}

read_target <- function(wd, name, store = "_targets") {
  targets::tar_read_raw(name, store = file.path(wd, store))
}

# Rebuilds one Target (and what it depends on) in a separate store with a
# different global seed. Returns the new value, or an error condition.
rebuild_with_new_seed <- function(wd, name) {
  wrapper <- file.path(wd, "_targets_reseed.R")
  # Targets take their seed when defined, so set it first, and keep the
  # Pipeline's own tar_option_set() calls from overriding it.
  writeLines(c(
    ".targetfy_env <- new.env()",
    ".targetfy_env$tar_option_set <- function(...) {",
    "  targets::tar_option_set(...)",
    "  targets::tar_option_set(seed = 987654321L)",
    "}",
    "targets::tar_option_set(seed = 987654321L)",
    "source('_targets.R', local = .targetfy_env)$value"
  ), wrapper)
  err <- build_pipeline(wd, script = "_targets_reseed.R",
                        store = "_targets_reseed", names = name)
  if (!is.null(err)) return(simpleError(err))
  tryCatch(read_target(wd, name, "_targets_reseed"), error = identity)
}

# Names a Target's command uses, following the project's own functions.
uses_random <- function(command, globals) {
  seen <- character()
  todo <- all.names(command)
  while (length(todo)) {
    n <- todo[[1]]
    todo <- todo[-1]
    if (n %in% seen) next
    seen <- c(seen, n)
    if (!is.null(globals[[n]])) todo <- c(todo, all.names(globals[[n]]))
  }
  intersect(seen, RANDOM_FUNS)
}

# Bodies of the Pipeline's own functions, by name. Loaded in a fresh session
# because tar_source() puts functions in the global environment.
load_globals <- function(wd) {
  tryCatch(callr::r(function(wd) {
    setwd(wd)
    targets::tar_load_globals(envir = globalenv())
    objs <- mget(ls(globalenv(), all.names = TRUE), envir = globalenv())
    lapply(Filter(is.function, objs), body)
  }, args = list(wd)), error = function(e) list())
}

# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------

# Removes what legitimately differs between a script and a function-wrapped
# version of the same code: a model's stored `call` and environments.
KEEP_ATTRS <- c("names", "dim", "dimnames", "row.names", "class", "levels")

normalize <- function(x) {
  if (is.environment(x) || is.function(x)) return(NULL)
  if (inherits(x, "formula")) return(paste(deparse(x), collapse = " "))
  at <- attributes(x)
  for (n in setdiff(names(at), KEEP_ATTRS)) attr(x, n) <- normalize(at[[n]])
  if (is.list(x)) {
    if (!is.null(names(x)) && !is.data.frame(x)) x <- x[names(x) != "call"]
    x[] <- lapply(x, normalize)
  }
  x
}

values_match <- function(a, b) {
  isTRUE(all.equal(normalize(a), normalize(b)))
}

structure_of <- function(x) {
  list(
    class = class(x),
    dim = dim(x),
    length = length(x),
    names = if (is.data.frame(x) || is.null(dim(x))) names(x) else NULL,
    column_types = if (is.data.frame(x)) vapply(x, function(c) class(c)[1], "")
  )
}

structure_match <- function(a, b) identical(structure_of(a), structure_of(b))

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

targetfy_check <- function(project, scripts, map = list(), mode = "equivalence",
                           max_copy_mb = 1024, allow_large = FALSE,
                           keep = FALSE) {
  project <- normalizePath(project, winslash = "/", mustWork = TRUE)
  result <- list(mode = mode, status = NULL, static = NULL, targets = list(),
                 files = list(), errors = list())
  missing_scripts <- scripts[!file.exists(file.path(project, scripts))]
  if (length(missing_scripts)) {
    result$status <- "error"
    result$errors <- list(paste("Source Script not found:", missing_scripts))
    return(result)
  }

  files <- project_files(project)
  size_mb <- sum(file.size(file.path(project, files))) / 1024^2
  result$copy_size_mb <- round(size_mb, 1)
  if (mode == "equivalence" && size_mb > max_copy_mb && !allow_large) {
    result$status <- "needs_confirmation"
    result$errors <- list(sprintf(
      "Project copy would be %.0f MB (limit %d MB): confirm, or use --mode static",
      size_mb, as.integer(max_copy_mb)))
    return(result)
  }

  root <- tempfile("targetfy-check-")
  if (!keep) on.exit(unlink(root, recursive = TRUE), add = TRUE)
  else result$workdir <- root
  pipe_dir <- copy_project(project, file.path(root, "pipeline"), files)

  result$static <- static_check(pipe_dir)
  if (mode == "static") {
    result$status <- if (static_ok(result$static)) "static_pass" else "static_fail"
    result$equivalence <- "unverified"
    return(result)
  }
  if (!static_ok(result$static)) {
    result$status <- "not_equivalent"
    result$errors <- list("Static Check failed")
    return(result)
  }

  # 1. Run the Script Sequence in its own copy.
  target_map <- map$targets %||% list()
  step_names <- unique(unlist(target_map[!vapply(target_map, is.null, TRUE)]))
  script_dir <- copy_project(project, file.path(root, "script"), files)
  before <- file_hashes(script_dir)
  snapshot <- file.path(root, "script-objects.rds")
  run <- run_scripts(script_dir, scripts, as.character(step_names), snapshot)
  if (!is.null(run$error)) {
    result$status <- "error"
    result$errors <- list(paste("Script Sequence failed:", run$error))
    return(result)
  }
  script_written <- written_files(before, file_hashes(script_dir))
  script_objects <- readRDS(snapshot)

  # 2. Build the Pipeline in its own copy.
  pipe_before <- file_hashes(pipe_dir)
  err <- build_pipeline(pipe_dir)
  if (!is.null(err)) {
    result$status <- "error"
    result$errors <- list(paste("Pipeline failed:", err))
    return(result)
  }
  pipe_hashes <- file_hashes(pipe_dir)

  # 3. Compare Targets with their Steps.
  manifest <- result$static$manifest
  globals <- load_globals(pipe_dir)
  flagged <- as.character(unlist(map$stochastic))
  for (i in seq_len(nrow(manifest))) {
    name <- manifest$name[[i]]
    step <- target_map[[name]]
    entry <- list(target = name, step = step %||% NA, stochastic = FALSE,
                  stochastic_reason = NA, result = NA)
    command <- tryCatch(parse(text = manifest$command[[i]]),
                        error = function(e) NULL)
    random <- uses_random(command, globals)
    if (name %in% flagged) {
      entry$stochastic <- TRUE
      entry$stochastic_reason <- "flagged by Conversion"
    } else if (length(random)) {
      entry$stochastic <- TRUE
      entry$stochastic_reason <- paste("calls", paste(random, collapse = ", "))
    }
    if (is.null(step)) {
      entry$result <- "not_compared"
    } else if (!step %in% names(script_objects)) {
      entry$result <- "step_missing"
    } else {
      value <- read_target(pipe_dir, name)
      expected <- script_objects[[step]]
      if (!entry$stochastic && values_match(value, expected)) {
        entry$result <- "match"
      } else {
        if (!entry$stochastic) {
          reseeded <- rebuild_with_new_seed(pipe_dir, name)
          if (!inherits(reseeded, "error") && !values_match(reseeded, value)) {
            entry$stochastic <- TRUE
            entry$stochastic_reason <- "value changes with the seed"
          }
        }
        entry$result <- if (!entry$stochastic) "mismatch"
          else if (structure_match(value, expected)) "structure_match"
          else "structure_mismatch"
        if (entry$result != "structure_match") {
          entry$detail <- paste(utils::capture.output(
            print(all.equal(normalize(value), normalize(expected)))),
            collapse = "\n")
        }
      }
    }
    result$targets[[length(result$targets) + 1]] <- entry
  }

  # 4. Compare files the Script Sequence wrote.
  handoff <- as.character(unlist(map$handoff_files))
  for (f in script_written) {
    entry <- list(file = f)
    ext <- tolower(tools::file_ext(f))
    if (f %in% handoff) {
      entry$result <- "handoff"
    } else if (!f %in% names(pipe_hashes) ||
               (f %in% names(pipe_before) &&
                  pipe_hashes[[f]] == pipe_before[[f]])) {
      entry$result <- "missing"
    } else if (pipe_hashes[[f]] == tools::md5sum(file.path(script_dir, f))) {
      entry$result <- "match"
    } else if (ext %in% LOOSE_FILE_EXT &&
               file.size(file.path(pipe_dir, f)) > 0) {
      entry$result <- "exists"
    } else {
      entry$result <- "mismatch"
    }
    result$files[[length(result$files) + 1]] <- entry
  }

  bad_targets <- vapply(result$targets, function(t)
    t$result %in% c("mismatch", "structure_mismatch", "step_missing"), TRUE)
  bad_files <- vapply(result$files, function(f)
    f$result %in% c("missing", "mismatch"), TRUE)
  result$status <- if (any(bad_targets) || any(bad_files)) "not_equivalent"
    else "equivalent"
  result
}

EXIT_CODES <- c(equivalent = 0, static_pass = 0, not_equivalent = 1,
                static_fail = 1, error = 2, needs_confirmation = 3)

parse_args <- function(args) {
  opts <- list(mode = "equivalence", max_copy_mb = 1024, allow_large = FALSE,
               keep = FALSE, map = NULL, out = NULL)
  i <- 1
  while (i <= length(args)) {
    key <- sub("^--", "", args[[i]])
    key <- gsub("-", "_", key)
    if (key %in% c("allow_large", "keep")) {
      opts[[key]] <- TRUE
      i <- i + 1
    } else {
      opts[[key]] <- args[[i + 1]]
      i <- i + 2
    }
  }
  opts$scripts <- strsplit(opts$scripts, ",", fixed = TRUE)[[1]]
  opts$max_copy_mb <- as.numeric(opts$max_copy_mb)
  opts
}

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  opts <- parse_args(args)
  map_path <- opts$map %||% file.path(opts$project, "targetfy-map.json")
  map <- if (file.exists(map_path))
    jsonlite::read_json(map_path, simplifyVector = FALSE) else list()
  result <- tryCatch(
    targetfy_check(opts$project, opts$scripts, map, opts$mode,
                   opts$max_copy_mb, opts$allow_large, opts$keep),
    error = function(e) list(status = "error", errors = list(conditionMessage(e)))
  )
  json <- jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE,
                           null = "null", na = "null", dataframe = "rows")
  if (is.null(opts$out)) cat(json, "\n") else writeLines(json, opts$out)
  quit(status = EXIT_CODES[[result$status]], save = "no")
}

if (sys.nframe() == 0L) main()
