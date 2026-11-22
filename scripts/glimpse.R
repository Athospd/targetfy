# targetfy glimpse: a lightweight picture of the Pipeline's graph.
#
# Usage:
#   Rscript glimpse.R --project DIR [--pipeline _targets.R] [--no-open]
#
# Saves targets::tar_glimpse() as an HTML page in a temp folder (never in
# DIR), opens it in the browser unless --no-open, and prints its path.
# tar_glimpse() only reads the Pipeline script; it builds nothing.

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  opts <- list(project = ".", pipeline = "_targets.R", open = TRUE)
  i <- 1
  while (i <= length(args)) {
    if (args[[i]] == "--no-open") {
      opts$open <- FALSE
      i <- i + 1
    } else {
      opts[[sub("^--", "", args[[i]])]] <- args[[i + 1]]
      i <- i + 2
    }
  }
  for (pkg in c("targets", "visNetwork", "htmlwidgets")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      message("glimpse needs the '", pkg, "' package, which is not installed")
      quit(status = 2, save = "no")
    }
  }
  setwd(opts$project)
  widget <- tryCatch(targets::tar_glimpse(script = opts$pipeline),
                     error = function(e) e)
  if (inherits(widget, "error")) {
    # Usually a package the Pipeline script attaches isn't installed.
    msg <- conditionMessage(widget)
    pkg <- regmatches(msg, regexpr("there is no package called [^\n]*", msg))
    message("glimpse could not read the Pipeline: ",
            if (length(pkg)) pkg else trimws(strsplit(msg, "\n")[[1]][1]))
    quit(status = 2, save = "no")
  }
  name <- tools::file_path_sans_ext(basename(opts$pipeline))
  # The system temp folder: R deletes its own session tempdir() on exit,
  # before the browser has loaded the page.
  out_dir <- tempfile("targetfy-glimpse-", tmpdir = dirname(tempdir()))
  dir.create(out_dir)
  out <- file.path(out_dir, paste0(name, "-glimpse.html"))
  selfcontained <- requireNamespace("rmarkdown", quietly = TRUE) &&
    rmarkdown::pandoc_available()
  htmlwidgets::saveWidget(widget, out, selfcontained = selfcontained,
                          title = paste("targetfy:", opts$pipeline))
  out <- normalizePath(out, winslash = "/")
  if (opts$open) utils::browseURL(out)
  cat(out, "\n")
}

if (sys.nframe() == 0L) main()
