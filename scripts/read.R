# targetfy read: what the Source Scripts do, read from their code.
#
# Usage:
#   Rscript read.R --project DIR --scripts a.R[,report.qmd,nb.ipynb...]
#                  [--tangle-dir TEMPDIR] [--out read.json]
#
# Runs nothing. For each Source Script it:
# - extracts a notebook's R code (.qmd, .Rmd, .md chunks; .ipynb code cells
#   of an R kernel) and, with --tangle-dir, writes it as <name>.R, each
#   chunk headed by the notebook line it came from;
# - scans the flow of names and files between top-level statements and
#   reports what a naive one-variable-one-Target Conversion would get wrong:
#   reassigned: a variable changed after another Step used it (versions);
#     cycle: TRUE when one Target would depend on itself
#   in_place_file: a file read and then overwritten
#   handoff: a file written and then read back
#   carried_loop: a loop or fold whose iterations feed each other
#   branch_candidate: a loop or apply call with independent iterations
#   global_state: <<-, assign(), options(), set.seed(), data.table by reference
#   defined_later: a name used before the statement that defines it
#
# Notebook problems (a Python-kernel notebook, an unreadable file) are
# reported per script, never fatal.

this_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(file)) dirname(normalizePath(file[[1]], winslash = "/")) else "."
}
sys.source(file.path(this_dir(), "check.R"), envir = environment())

main_read <- function(args = commandArgs(trailingOnly = TRUE)) {
  opts <- list(project = ".", scripts = NULL, tangle_dir = NULL, out = NULL)
  i <- 1
  while (i <= length(args)) {
    opts[[gsub("-", "_", sub("^--", "", args[[i]]))]] <- args[[i + 1]]
    i <- i + 2
  }
  scripts <- strsplit(opts$scripts, ",", fixed = TRUE)[[1]]
  res <- flow_scan(opts$project, scripts)
  if (!is.null(opts$tangle_dir)) {
    dir.create(opts$tangle_dir, recursive = TRUE, showWarnings = FALSE)
    for (s in scripts) {
      if (!is_notebook(s)) next
      t <- tryCatch(tangle(file.path(opts$project, s)), error = function(e) NULL)
      if (is.null(t)) next
      out <- file.path(opts$tangle_dir,
                       paste0(gsub("[/\\\\]", "__", s), ".R"))
      writeLines(tangled_lines(s, t), out, useBytes = TRUE)
      res$scripts[[s]]$tangled <- normalizePath(out, winslash = "/")
    }
  }
  json <- jsonlite::toJSON(res, auto_unbox = TRUE, pretty = TRUE,
                           null = "null", na = "null")
  if (is.null(opts$out)) cat(json, "\n") else writeLines(json, opts$out)
}

main_read()
