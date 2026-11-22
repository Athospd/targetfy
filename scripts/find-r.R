# targetfy find-r: picks the R installation to use for the check.
#
# Usage (run with any Rscript):
#   Rscript find-r.R [--project DIR --scripts a.R[,b.R...]] [--out result.json]
#
# Finds every R installation on the machine, and in a fresh session of each
# one tries to load targetfy's packages plus every package the Source
# Scripts need (read from their code, never run). Loading, not just looking
# for the folder, catches version conflicts such as "namespace 'yardstick'
# 1.3.1 is being loaded, but >= 1.4.0 is required".
#
# Picks the installation where everything loads: the one on the PATH if it
# qualifies, otherwise the highest version. If none loads everything, it
# picks the one with the fewest problems (ties: PATH, then highest version)
# and lists what's missing in each, so the user can decide what to install.
# Installs nothing.

`%||%` <- function(a, b) if (is.null(a)) b else a

TARGETFY_PACKAGES <- c("targets", "tarchetypes", "callr", "jsonlite")

this_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(file)) dirname(normalizePath(file[[1]], winslash = "/"))
  else "."
}

rscript_name <- function() if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"

# Every Rscript we can find, de-duplicated by real path.
find_installations <- function() {
  exe <- rscript_name()
  on_path <- Sys.which(sub("\\.exe$", "", exe))
  cands <- c(
    on_path,
    file.path(R.home("bin"), exe),
    Sys.glob(file.path(Sys.getenv("ProgramFiles", "C:/Program Files"),
                       "R", "R-*", "bin", exe)),
    Sys.glob(file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "R",
                       "R-*", "bin", exe)),
    Sys.glob("/Library/Frameworks/R.framework/Versions/*/Resources/bin/Rscript"),
    Sys.glob("/opt/R/*/bin/Rscript"),
    Sys.glob("/usr/lib/R/bin/Rscript"),
    Sys.glob("/usr/local/bin/Rscript"),
    Sys.glob("/usr/bin/Rscript")
  )
  cands <- cands[nzchar(cands) & file.exists(cands)]
  # On Windows, bin/Rscript.exe and bin/x64/Rscript.exe are the same R:
  # compare installations by their home folder.
  home_of <- function(p) tolower(sub("/bin(/x64)?/Rscript(\\.exe)?$", "",
    normalizePath(p, winslash = "/", mustWork = FALSE), ignore.case = TRUE))
  real <- normalizePath(cands, winslash = "/", mustWork = FALSE)
  home <- home_of(real)
  keep <- !duplicated(home)
  path_home <- if (nzchar(on_path)) home_of(on_path) else ""
  data.frame(rscript = real[keep], on_path = home[keep] == path_home,
             stringsAsFactors = FALSE)
}

# Runs in the candidate R. Writes version and per-package load results.
probe_code <- function(pkgs, out) {
  sprintf(paste0(
    "pk <- c(%s); res <- lapply(pk, function(p) tryCatch({",
    "suppressPackageStartupMessages(loadNamespace(p)); NULL}, ",
    "error = function(e) conditionMessage(e))); names(res) <- pk; ",
    "saveRDS(list(version = paste(R.version$major, R.version$minor, sep = '.'), ",
    "errors = Filter(Negate(is.null), res)), %s)"),
    paste0("'", pkgs, "'", collapse = ", "), deparse(out))
}

# R sets R_HOME, R_ARCH, R_LIBS_SITE and R_LIBS_USER for itself at startup,
# and a child R inherits them: another version would then load *this*
# version's packages. Clear the ones R set (those pointing at this R's own
# home or at this version's default library); keep any the user set.
clean_r_env <- function() {
  ver <- paste0("/", R.version$major, ".", sub("\\..*$", "", R.version$minor), "$")
  home <- tolower(normalizePath(R.home(), winslash = "/", mustWork = FALSE))
  ours <- function(v) {
    val <- Sys.getenv(v)
    if (!nzchar(val)) return(FALSE)
    norm <- tolower(normalizePath(val, winslash = "/", mustWork = FALSE))
    startsWith(norm, home) || grepl(ver, sub("/$", "", norm))
  }
  vars <- c("R_HOME", "R_ARCH", "R_LIBS_SITE", "R_LIBS_USER", "R_SHARE_DIR",
            "R_INCLUDE_DIR", "R_DOC_DIR")
  drop <- vars[vapply(vars, ours, NA) | vars %in% c("R_HOME", "R_ARCH")]
  saved <- Sys.getenv(drop, unset = NA, names = TRUE)
  Sys.unsetenv(drop)
  saved[!is.na(saved)]
}

probe <- function(rscript, pkgs) {
  saved <- clean_r_env()
  on.exit(do.call(Sys.setenv, as.list(saved)), add = TRUE)
  out <- tempfile(fileext = ".rds")
  script <- tempfile(fileext = ".R")
  writeLines(probe_code(pkgs, normalizePath(out, winslash = "/", mustWork = FALSE)),
             script)
  # No --vanilla: the check runs with the user's .Renviron and .Rprofile,
  # which may set library paths, so the probe must too.
  status <- suppressWarnings(system2(rscript, shQuote(script),
                                     stdout = FALSE, stderr = FALSE))
  if (!file.exists(out)) {
    return(list(version = NA, works = FALSE,
                problems = list(list(package = NA,
                  message = paste("this R didn't start (exit", status, ")")))))
  }
  r <- readRDS(out)
  problems <- lapply(names(r$errors), function(p) list(
    package = p,
    message = if (grepl("there is no package called", r$errors[[p]], fixed = TRUE))
      "not installed" else r$errors[[p]]))
  list(version = r$version, works = length(problems) == 0, problems = problems)
}

version_key <- function(v) {
  v <- ifelse(is.na(v), "0.0.0", v)
  vapply(v, function(x) sum(as.numeric(strsplit(x, ".", fixed = TRUE)[[1]][1:3]) *
                              c(1e6, 1e3, 1)), 0)
}

find_r <- function(project = NULL, scripts = character()) {
  pkgs <- TARGETFY_PACKAGES
  if (length(scripts)) {
    env <- new.env()
    sys.source(file.path(this_dir(), "check.R"), envir = env)
    paths <- file.path(project %||% ".", scripts)
    pkgs <- unique(c(pkgs, env$required_packages(paths)))
  }
  base_pkgs <- rownames(installed.packages(priority = "base"))
  pkgs <- setdiff(pkgs, base_pkgs)
  inst <- find_installations()
  results <- lapply(seq_len(nrow(inst)), function(i) {
    p <- probe(inst$rscript[[i]], pkgs)
    c(list(rscript = inst$rscript[[i]], on_path = inst$on_path[[i]]), p)
  })
  if (!length(results)) {
    return(list(status = "no_r", packages = pkgs, installations = list(),
                chosen = NULL))
  }
  works <- vapply(results, `[[`, NA, "works")
  n_prob <- vapply(results, function(r) length(r$problems), 0)
  on_path <- vapply(results, `[[`, NA, "on_path")
  vkey <- version_key(vapply(results, function(r) r$version %||% NA_character_, ""))
  ord <- order(-works, n_prob, -on_path, -vkey)
  chosen <- results[[ord[[1]]]]
  list(
    status = if (chosen$works) "ok" else "missing_packages",
    packages = pkgs,
    chosen = chosen$rscript,
    chosen_version = chosen$version,
    chosen_is_path = chosen$on_path,
    installations = results
  )
}

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  opts <- list(project = NULL, scripts = NULL, out = NULL)
  i <- 1
  while (i <= length(args)) {
    opts[[sub("^--", "", args[[i]])]] <- args[[i + 1]]
    i <- i + 2
  }
  scripts <- if (is.null(opts$scripts)) character()
    else strsplit(opts$scripts, ",", fixed = TRUE)[[1]]
  res <- find_r(opts$project, scripts)
  json <- jsonlite::toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (is.null(opts$out)) cat(json, "\n") else writeLines(json, opts$out)
}

if (sys.nframe() == 0L) main()
