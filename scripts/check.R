# targetfy check: decides whether a Conversion is accepted (see docs/adr/0001).
#
# Usage:
#   Rscript check.R --project DIR --scripts a.R[,b.R...]
#                   [--pipeline _targets.R]   (or targets_<name>.R)
#                   [--map map.json]   (default: the Pipeline's Step Map,
#                                       DIR/targetfy-map[_<name>].json)
#                   [--mode equivalence|static] [--max-copy-mb 1024]
#                   [--allow-large] [--keep] [--out result.json]
#
# Never touches DIR: every run happens in throwaway copies.
#
# --scripts takes .R files and notebooks (.qmd, .Rmd, .md, R-kernel
# .ipynb); a notebook's R code runs from its own folder, as rendering does.
# The Pipeline must also be up to date right after it's built (else
# outdated_after_build, not_equivalent), and a file the scripts overwrite
# in place is compared at the Step Map's redirected_files path.
#
# Exit codes: 0 equivalent / static_pass (also when the scripts themselves
#             fail: see script_failure) / not_checked (a package the code
#             needs isn't installed: see missing_packages),
#             1 not_equivalent / static_fail,
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

# "^_targets[^/]*/" covers every store: _targets/, _targets_<name>/, reseed.
COPY_EXCLUDE <- c("^\\.git/", "^_targets[^/]*/",
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
# Notebooks: .qmd, .Rmd, .md and .ipynb Source Scripts
# ---------------------------------------------------------------------------
# A notebook's R code chunks (or an R-kernel notebook's code cells), in
# order, are its Source Script; the prose is dropped. `tangle()` extracts
# them with a map back to the notebook's own lines, so failures and Steps
# can be reported as `report.qmd:42` or `nb.ipynb:cell 3, line 2`.

NOTEBOOK_EXT <- c("qmd", "rmd", "rmarkdown", "md", "ipynb")

is_notebook <- function(path) tolower(tools::file_ext(path)) %in% NOTEBOOK_EXT

# Rmd/qmd run only braced chunks (```{r}); a plain ```r fence is display
# code. A .md file is never knitted, so both kinds count as its code.
CHUNK_OPEN <- "^([ \t>]*)(`{3,}|~{3,})[ \t]*(\\{[ \t]*\\.?([A-Za-z0-9_]+)([^}]*)\\}|([A-Za-z0-9_]+))?[ \t]*$"

chunk_false <- function(header, opt_lines, opt) {
  in_header <- grepl(sprintf("(^|[ ,])%s[ \t]*=[ \t]*(FALSE|F)\\b", opt), header)
  in_yaml <- any(grepl(sprintf("^#\\|[ \t]*%s:[ \t]*false\\b", opt), opt_lines))
  in_header || in_yaml
}

# The working directory a notebook's code runs in: knitr and Quarto run it
# from the notebook's own folder, unless a _quarto.yml sets
# `execute-dir: project`.
notebook_wd <- function(project, path) {
  dir <- dirname(path)
  if (tolower(tools::file_ext(path)) != "qmd") return(dir)
  d <- dir
  repeat {
    yml <- file.path(project, d, "_quarto.yml")
    if (file.exists(yml) &&
        any(grepl("execute-dir:[ \t]*project", readLines(yml, warn = FALSE))))
      return(d)
    if (d %in% c(".", "", "/")) break
    d <- dirname(d)
  }
  dir
}

tangle_text <- function(lines, ext) {
  braced_only <- ext != "md"
  code <- character(); src <- integer(); chunks <- list(); skipped <- list()
  inline <- list(); warnings <- character()
  # YAML front matter: skipped, but its params become a `params` list.
  body_start <- 1L
  if (length(lines) && trimws(lines[[1]]) == "---") {
    end <- which(trimws(lines[-1]) %in% c("---", "..."))
    if (length(end)) body_start <- end[[1]] + 2L
  }
  params <- NULL
  if (ext %in% c("qmd", "rmd", "rmarkdown") && body_start > 1L &&
      requireNamespace("knitr", quietly = TRUE)) {
    p <- tryCatch(knitr::knit_params(paste(lines[seq_len(body_start - 1L)],
                                           collapse = "\n")),
                  error = function(e) NULL)
    if (length(p)) params <- lapply(p, `[[`, "value")
  }
  i <- body_start
  n <- length(lines)
  while (i <= n) {
    m <- regmatches(lines[[i]], regexec(CHUNK_OPEN, lines[[i]]))[[1]]
    if (!length(m)) {
      # Inline code: `r expr` (Rmd) and `{r} expr` (qmd).
      hits <- regmatches(lines[[i]], gregexpr("`(\\{r\\}|r) [^`]+`", lines[[i]]))[[1]]
      for (h in hits) inline[[length(inline) + 1]] <- list(
        line = i, code = sub("^`(\\{r\\}|r) ", "", sub("`$", "", h)))
      i <- i + 1L
      next
    }
    indent <- m[[2]]; fence <- m[[3]]
    lang <- tolower(if (nzchar(m[[5]])) m[[5]] else m[[7]])
    braced <- nzchar(m[[5]])
    header <- m[[6]]
    close_re <- sprintf("^[ \t>]*%s%s*[ \t]*$", substr(fence, 1, 1),
                        strrep(substr(fence, 1, 1), nchar(fence) - 1))
    j <- i + 1L
    while (j <= n && !grepl(close_re, lines[[j]])) j <- j + 1L
    body_idx <- if (j > i + 1L) seq.int(i + 1L, j - 1L) else integer()
    body <- substring(lines[body_idx], nchar(indent) + 1L)
    opt_lines <- grep("^#\\|", body, value = TRUE)
    label <- sub("^[ \t,]*([^ ,=]+)([ \t,].*)?$", "\\1", header)
    label <- if (nzchar(trimws(header)) && !grepl("=", strsplit(header, ",")[[1]][1]))
      trimws(label) else NA_character_
    yl <- sub("^#\\|[ \t]*label:[ \t]*", "", grep("^#\\|[ \t]*label:", opt_lines, value = TRUE))
    if (length(yl)) label <- trimws(yl[[1]])
    is_code <- lang == "r" && (braced || !braced_only)
    if (lang != "" && !is_code && (braced || !braced_only)) {
      skipped[[length(skipped) + 1]] <- list(line = i, lang = lang,
        reason = if (lang %in% c("python", "bash", "sh", "sql", "julia", "js", "ojs"))
          paste(lang, "chunk: not R, so not converted") else
          paste(lang, "chunk: not R code"))
    } else if (is_code) {
      if (chunk_false(header, opt_lines, "eval")) {
        skipped[[length(skipped) + 1]] <- list(line = i, lang = "r",
          label = label, reason = "eval = FALSE: never runs")
      } else {
        if (grepl("eval[ \t]*=", header) || any(grepl("^#\\|[ \t]*eval:", opt_lines)))
          warnings <- c(warnings, sprintf(
            "line %d: chunk `eval` set by an expression; treated as running", i))
        if (grepl("error[ \t]*=[ \t]*(TRUE|T)\\b", header) ||
            any(grepl("^#\\|[ \t]*error:[ \t]*true", opt_lines)))
          warnings <- c(warnings, sprintf(
            "line %d: chunk has error = TRUE; knitting continues past its errors, the check does not", i))
        if (any(grepl("^[ \t]*<<[^>]+>>[ \t]*$", body)))
          warnings <- c(warnings, sprintf(
            "line %d: chunk reuses another chunk (<<label>>); not expanded", i))
        chunks[[length(chunks) + 1]] <- list(label = label, start = i,
                                             end = j, lines = length(body))
        code <- c(code, body)
        src <- c(src, body_idx)
      }
    }
    i <- j + 1L
  }
  list(code = code, src = src, cell = rep(NA_integer_, length(code)),
       chunks = chunks, skipped = skipped, inline = inline,
       params = params, warnings = warnings)
}

tangle_ipynb <- function(path) {
  nb <- jsonlite::read_json(path, simplifyVector = FALSE)
  lang <- nb$metadata$kernelspec$language %||% nb$metadata$language_info$name %||% ""
  if (tolower(lang) != "r")
    stop(sprintf("%s uses a %s kernel, not R: only R notebooks are supported",
                 basename(path), if (nzchar(lang)) lang else "non-R"), call. = FALSE)
  code <- character(); src <- integer(); cell <- integer(); chunks <- list()
  warnings <- character()
  k <- 0L
  for (c in nb$cells) {
    k <- k + 1L
    if (!identical(c$cell_type, "code")) next
    s <- paste(unlist(c$source), collapse = "")
    body <- strsplit(s, "\n", fixed = TRUE)[[1]]
    if (!length(body)) next
    magic <- grepl("^[ \t]*[%!]", body)
    if (any(magic)) {
      warnings <- c(warnings, sprintf("cell %d: magic or shell lines dropped", k))
      body[magic] <- paste("#", body[magic])
    }
    chunks[[length(chunks) + 1]] <- list(label = NA, cell = k, lines = length(body))
    code <- c(code, body); src <- c(src, seq_along(body)); cell <- c(cell, rep(k, length(body)))
  }
  list(code = code, src = src, cell = cell, chunks = chunks, skipped = list(),
       inline = list(), params = NULL, warnings = warnings)
}

# A Source Script's code, as lines, with each line's place in the file.
# For a plain .R file this is just the file.
tangle <- function(path) {
  ext <- tolower(tools::file_ext(path))
  t <- if (ext == "ipynb") tangle_ipynb(path)
    else if (ext %in% NOTEBOOK_EXT) tangle_text(readLines(path, warn = FALSE, encoding = "UTF-8"),
                                                if (ext == "rmarkdown") "rmd" else ext)
    else {
      lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
      list(code = lines, src = seq_along(lines), cell = rep(NA_integer_, length(lines)),
           chunks = list(), skipped = list(), inline = list(), params = NULL,
           warnings = character())
    }
  t$notebook <- ext %in% NOTEBOOK_EXT
  # Notebook params (YAML `params:`) are defined first, as knitting does.
  if (length(t$params)) {
    def <- paste0("params <- ", paste(deparse(t$params), collapse = " "))
    t$code <- c(def, t$code); t$src <- c(NA_integer_, t$src); t$cell <- c(NA_integer_, t$cell)
  }
  t
}

# "report.qmd:42", or "nb.ipynb:cell 3, line 2".
origin_label <- function(script, t, i) {
  if (is.na(i) || i > length(t$src) || is.na(t$src[[i]]))
    return(paste0(script, " (YAML params)"))
  if (!is.na(t$cell[[i]])) sprintf("%s:cell %d, line %d", script, t$cell[[i]], t$src[[i]])
  else sprintf("%s:%d", script, t$src[[i]])
}

# The tangled code written as an .R file for reading, each chunk headed by
# where it came from.
tangled_lines <- function(script, t) {
  if (!t$notebook) return(t$code)
  out <- character(); prev <- -1L
  for (i in seq_along(t$code)) {
    start <- is.na(t$src[[i]]) && i == 1L ||
      (!is.na(t$src[[i]]) && (prev < 0L || is.na(t$src[[i - 1L]]) ||
        t$src[[i]] != t$src[[i - 1L]] + 1L ||
        !identical(t$cell[[i]], t$cell[[i - 1L]])))
    if (start) out <- c(out, sprintf("# ---- %s ----", origin_label(script, t, i)))
    out <- c(out, t$code[[i]])
    prev <- i
  }
  out
}

parse_code <- function(path) {
  t <- tangle(path)
  parse(text = t$code, keep.source = TRUE)
}

# ---------------------------------------------------------------------------
# Flow scan: what each top-level statement reads and writes
# ---------------------------------------------------------------------------
# A script is a sequence, not a graph: the same name can hold several
# values over time, a file can be read and then overwritten, and a loop can
# feed each iteration into the next. Mapped naively (one variable, one
# Target) these become cycles. The scan finds them, read from the code
# without running it, so the Conversion can give each version its own
# Target, redirect in-place files and keep carried loops inside one Target.

READ_FUNS <- c("read.csv", "read.csv2", "read.table", "read.delim", "readRDS",
  "load", "readLines", "read_csv", "read_csv2", "read_tsv", "read_delim",
  "read_rds", "fread", "read_excel", "read_xlsx", "read_xls", "read_parquet",
  "read_feather", "vroom", "read_fst", "read_sav", "read_dta", "read_sas",
  "read_json", "fromJSON", "st_read", "read_sf", "read_lines", "scan")
WRITE_FUNS <- c(write.csv = 2, write.csv2 = 2, write.table = 2, saveRDS = 2,
  writeLines = 2, write_csv = 2, write_csv2 = 2, write_tsv = 2,
  write_delim = 2, write_rds = 2, fwrite = 2, write_xlsx = 2,
  write_parquet = 2, write_feather = 2, write_json = 2, st_write = 2,
  saveWidget = 2, write_lines = 2, ggsave = 1, png = 1, pdf = 1, jpeg = 1,
  svg = 1, tiff = 1, bmp = 1, sink = 1, save = NA)
FILE_ARGS <- c("file", "path", "filename", "con", "sink", "dsn", "txt", "x")
BY_REFERENCE <- c("set", "setnames", "setDT", "setorder", "setorderv",
                  "setkey", "setkeyv", "setattr", "setcolorder", "setDF")
APPLY_FUNS <- c("lapply", "sapply", "vapply", "Map", "mapply", "map",
  "map_dfr", "map_dfc", "map_df", "map_chr", "map_dbl", "map_int", "map_lgl",
  "imap", "pmap", "map2", "walk", "future_map", "future_lapply", "parLapply",
  "mclapply", "group_map", "by", "tapply")
CARRY_FUNS <- c("Reduce", "accumulate", "reduce")
APPEND_FUNS <- c("c", "rbind", "cbind", "append", "bind_rows", "bind_cols",
                 "list", "rbindlist")

# A literal path: "a.csv", file.path("data", "a.csv"), here::here(...).
literal_path <- function(e) {
  if (is.character(e) && length(e) == 1) return(e)
  if (!is.call(e)) return(NULL)
  f <- e[[1]]
  fname <- if (is.symbol(f)) as.character(f)
    else if (is.call(f) && identical(f[[1]], quote(`::`))) as.character(f[[3]]) else ""
  if (!fname %in% c("file.path", "here", "paste0")) return(NULL)
  parts <- lapply(as.list(e)[-1], literal_path)
  if (any(vapply(parts, is.null, TRUE))) return(NULL)
  paste(unlist(parts), collapse = if (fname == "paste0") "" else "/")
}

file_arg <- function(e, pos) {
  args <- as.list(e)[-1]
  nm <- names(args) %||% rep("", length(args))
  named <- which(nm %in% FILE_ARGS)
  if (length(named)) return(literal_path(args[[named[[1]]]]))
  unnamed <- which(!nzchar(nm))
  if (is.na(pos) || length(unnamed) < pos) return(NULL)
  literal_path(args[[unnamed[[pos]]]])
}

call_name <- function(e) {
  f <- e[[1]]
  if (is.symbol(f)) as.character(f)
  else if (is.call(f) && (identical(f[[1]], quote(`::`)) ||
                          identical(f[[1]], quote(`:::`)))) as.character(f[[3]])
  else ""
}

# The variable an assignment's left side changes: x, x$a, x[i], names(x).
lhs_symbol <- function(lhs) {
  while (is.call(lhs)) lhs <- lhs[[2]]
  if (is.symbol(lhs) || is.character(lhs)) as.character(lhs) else NA_character_
}

new_flow <- function() {
  st <- new.env()
  st$reads <- character(); st$writes <- character(); st$files_read <- character()
  st$files_written <- character(); st$flags <- character(); st$assigns <- list()
  st$loops <- list(); st$applies <- character()
  st
}

flow_walk <- function(e, st) {
  if (is.symbol(e)) {
    if (!identical(e, quote(expr = ))) st$reads <- c(st$reads, as.character(e))
    return(invisible(st))
  }
  if (!is.call(e)) return(invisible(st))
  fname <- call_name(e)
  if (is.symbol(e[[1]])) st$reads <- c(st$reads, fname)
  else flow_walk(e[[1]], st)
  args <- if (length(e) > 1) as.list(e)[-1] else list()
  # Index, don't loop: binding an empty argument (x[, 1]) makes it missing.
  walk_args <- function(a, into = st) {
    for (k in seq_along(a)) if (!identical(a[[k]], quote(expr = ))) flow_walk(a[[k]], into)
  }
  if (fname %in% c("<-", "=", "<<-") && length(e) == 3) {
    lhs <- e[[2]]
    target <- lhs_symbol(lhs)
    if (fname == "<<-") st$flags <- c(st$flags, "global_assign")
    before <- length(st$reads)
    flow_walk(e[[3]], st)
    rhs_reads <- st$reads[seq_len(length(st$reads) - before) + before]
    if (is.call(lhs)) {
      # x[i] <- v reads x and i; record the index for loop analysis.
      li <- as.list(lhs)
      idx <- unlist(lapply(seq_along(li)[-(1:2)], function(k)
        if (identical(li[[k]], quote(expr = ))) character() else all.names(li[[k]])))
      walk_args(as.list(lhs)[-1])
    } else idx <- character()
    rhs_fn <- if (is.call(e[[3]])) call_name(e[[3]]) else ""
    rhs_args <- if (is.call(e[[3]])) as.list(e[[3]])[-1] else list()
    appends <- rhs_fn %in% APPEND_FUNS && !is.na(target) &&
      any(vapply(seq_along(rhs_args), function(k) identical(rhs_args[[k]], as.name(target)), TRUE))
    st$writes <- c(st$writes, target)
    if (rhs_fn == "function") st$flags <- c(st$flags, "function_def")
    st$assigns[[length(st$assigns) + 1]] <- list(target = target,
      partial = is.call(lhs), index = idx, rhs_reads = rhs_reads, appends = appends)
    return(invisible(st))
  }
  if (fname == "function") {
    inner <- new_flow()
    flow_walk(e[[3]], inner)
    local <- c(names(e[[2]]), inner$writes)
    st$reads <- c(st$reads, setdiff(inner$reads, local))
    st$files_read <- c(st$files_read, inner$files_read)
    st$files_written <- c(st$files_written, inner$files_written)
    st$flags <- c(st$flags, setdiff(inner$flags, "function_def"))
    return(invisible(st))
  }
  if (fname %in% c("~", "quote", "bquote", "expression")) return(invisible(st))
  if (fname %in% c("$", "@")) { flow_walk(e[[2]], st); return(invisible(st)) }
  if (fname == "for") {
    body <- new_flow()
    flow_walk(e[[4]], body)
    flow_walk(e[[3]], st)
    var <- as.character(e[[2]])
    st$loops[[length(st$loops) + 1]] <- list(kind = "for", var = var,
      over = paste(deparse(e[[3]]), collapse = " "), body = body)
    st$writes <- c(st$writes, var, body$writes)
    st$reads <- c(st$reads, body$reads)
    for (f in c("files_read", "files_written", "flags", "applies"))
      st[[f]] <- c(st[[f]], body[[f]])
    return(invisible(st))
  }
  if (fname %in% c("while", "repeat")) {
    body <- new_flow()
    walk_args(args, body)
    st$loops[[length(st$loops) + 1]] <- list(kind = fname, var = NA, over = NA, body = body)
    for (f in c("reads", "writes", "files_read", "files_written", "flags", "applies"))
      st[[f]] <- c(st[[f]], body[[f]])
    return(invisible(st))
  }
  if (fname %in% c("assign") && length(args) >= 2 && is.character(args[[1]])) {
    st$writes <- c(st$writes, args[[1]])
    st$flags <- c(st$flags, "assign")
  }
  if (fname == "%<>%") st$writes <- c(st$writes, lhs_symbol(e[[2]]))
  if (fname == "[" && any(vapply(seq_along(args), function(k) is.call(args[[k]]) &&
                                   identical(args[[k]][[1]], quote(`:=`)), TRUE))) {
    st$writes <- c(st$writes, lhs_symbol(e[[2]]))
    st$flags <- c(st$flags, "by_reference")
  }
  if (fname %in% BY_REFERENCE && length(args)) {
    st$writes <- c(st$writes, lhs_symbol(args[[1]]))
    st$flags <- c(st$flags, "by_reference")
  }
  if (fname %in% c("options", "Sys.setenv", "set.seed", "attach", "Sys.setlocale"))
    st$flags <- c(st$flags, fname)
  if (fname %in% READ_FUNS) {
    p <- file_arg(e, 1)
    if (!is.null(p)) st$files_read <- c(st$files_read, p)
  }
  if (fname %in% names(WRITE_FUNS)) {
    p <- file_arg(e, WRITE_FUNS[[fname]])
    if (!is.null(p)) st$files_written <- c(st$files_written, p)
  }
  if (fname %in% APPLY_FUNS) st$applies <- c(st$applies, fname)
  if (fname %in% CARRY_FUNS) st$flags <- c(st$flags, "carried_reduce")
  walk_args(args)
  invisible(st)
}

# A loop's iterations are independent when every variable it changes is
# either local to one iteration or a collection filled at the loop
# variable's position (res[[i]] <- ...) or appended to (res <- c(res, ...)).
# A variable whose new value reads its old one carries state.
classify_loop <- function(loop, defined_before) {
  if (loop$kind != "for") return(list(kind = "carried",
    carried = unique(intersect(loop$body$writes, loop$body$reads))))
  carried <- character(); collects <- character()
  # fresh: set from scratch earlier in this iteration, so local to it.
  # derived: the loop variable and what's computed from it.
  fresh <- character(); derived <- loop$var
  for (a in loop$body$assigns) {
    w <- a$target
    if (is.na(w)) next
    if (!a$partial && !w %in% a$rhs_reads) {
      fresh <- c(fresh, w)
      if (any(a$rhs_reads %in% derived)) derived <- c(derived, w)
      next
    }
    if (w %in% fresh) next
    if (a$partial && any(derived %in% a$index) && !w %in% a$rhs_reads) collects <- c(collects, w)
    else if (a$appends) collects <- c(collects, w)
    else carried <- c(carried, w)
  }
  carried <- setdiff(unique(carried), collects)
  list(kind = if (length(carried)) "carried" else "independent",
       carried = carried, collects = unique(collects))
}

flow_scan <- function(project, scripts) {
  statements <- list(); script_info <- list()
  for (s in scripts) {
    path <- file.path(project, s)
    t <- tryCatch(tangle(path), error = function(e) e)
    if (inherits(t, "error")) {
      script_info[[s]] <- list(error = conditionMessage(t))
      next
    }
    exprs <- tryCatch(parse(text = t$code, keep.source = TRUE), error = function(e) e)
    script_info[[s]] <- list(notebook = t$notebook, chunks = t$chunks,
      skipped = t$skipped, inline = t$inline, params = names(t$params),
      warnings = t$warnings, parse_error = if (inherits(exprs, "error"))
        conditionMessage(exprs))
    if (inherits(exprs, "error")) next
    refs <- attr(exprs, "srcref")
    for (i in seq_along(exprs)) {
      st <- new_flow()
      flow_walk(exprs[[i]], st)
      k <- refs[[i]][[1]]
      statements[[length(statements) + 1]] <- list(
        script = s, where = origin_label(s, t, k), st = st,
        code = paste(trimws(as.character(refs[[i]]))[1], collapse = ""))
    }
  }
  vars <- unique(stats::na.omit(unlist(lapply(statements, function(x) x$st$writes))))
  findings <- list()
  add <- function(...) findings[[length(findings) + 1]] <<- list(...)
  writes_of <- lapply(statements, function(x) unique(stats::na.omit(x$st$writes)))
  reads_of <- lapply(statements, function(x) unique(intersect(x$st$reads, vars)))
  n <- length(statements)

  # 1. Variables changed after another Step used them: versions.
  for (v in vars) {
    w <- which(vapply(writes_of, function(x) v %in% x, TRUE))
    users <- which(vapply(seq_len(n), function(i)
      v %in% reads_of[[i]] && length(setdiff(writes_of[[i]], v)) > 0, TRUE))
    for (r in users) {
      later <- w[w > r]
      if (!length(later) || !any(w < r)) next
      first_later <- later[[1]]
      # A cycle if the later version reads what was built from the earlier.
      built <- setdiff(writes_of[[r]], v)
      for (j in seq_len(first_later - r - 1L) + r)
        if (any(reads_of[[j]] %in% built)) built <- c(built, setdiff(writes_of[[j]], v))
      cycle <- any(reads_of[[first_later]] %in% built)
      cycle_txt <- if (cycle) sprintf(
        ", and the new version reads that result: one `%s` Target would depend on itself", v)
        else ""
      add(kind = "reassigned", name = v, used_at = statements[[r]]$where,
          used_by = I(setdiff(writes_of[[r]], v)),
          changed_at = statements[[first_later]]$where, cycle = cycle,
          message = sprintf(paste0(
            "`%s` is changed at %s after %s used it to build `%s`%s. ",
            "Give each version its own Target (for example `%s` and `%s_<what changed>`); ",
            "map only the last one to `%s`."),
            v, statements[[first_later]]$where, statements[[r]]$where,
            paste(setdiff(writes_of[[r]], v), collapse = "`, `"), cycle_txt,
            v, v, v))
      break
    }
  }

  # 2. Files: read then overwritten (in place), or written then read back.
  fr <- lapply(statements, function(x) unique(x$st$files_read))
  fw <- lapply(statements, function(x) unique(x$st$files_written))
  for (p in unique(c(unlist(fr), unlist(fw)))) {
    r <- which(vapply(fr, function(x) p %in% x, TRUE))
    w <- which(vapply(fw, function(x) p %in% x, TRUE))
    if (!length(r) || !length(w)) next
    if (any(w >= r[[1]])) {
      add(kind = "in_place_file", path = p, read_at = statements[[r[[1]]]]$where,
          written_at = statements[[max(w)]]$where,
          message = sprintf(paste0(
            "`%s` is read at %s and overwritten at %s. A Pipeline that writes its own ",
            "input is never up to date. Write the new version to another path ",
            "(record it in the Step Map's `redirected_files`), or ask the user."),
            p, statements[[r[[1]]]]$where, statements[[max(w)]]$where))
    }
    if (w[[1]] < max(r)) {
      add(kind = "handoff", path = p, written_at = statements[[w[[1]]]]$where,
          read_at = statements[[r[[length(r)]]]]$where,
          message = sprintf(paste0("`%s` is written at %s and read back at %s: ",
            "a Handoff File, unless it's also a result the user keeps."),
            p, statements[[w[[1]]]]$where, statements[[r[[length(r)]]]]$where))
    }
  }

  # 3. Loops and apply calls.
  for (i in seq_len(n)) {
    st <- statements[[i]]$st
    defined_before <- unique(unlist(writes_of[seq_len(i - 1L)]))
    for (lp in st$loops) {
      cl <- classify_loop(lp, defined_before)
      if (cl$kind == "carried") {
        add(kind = "carried_loop", where = statements[[i]]$where,
            loop = lp$kind, carried = I(cl$carried),
            message = sprintf(paste0(
              "The %s loop at %s carries state between iterations (%s). ",
              "Keep the whole loop inside one Target: iterations can't be separate Targets."),
              lp$kind, statements[[i]]$where,
              if (length(cl$carried)) paste0("`", cl$carried, "`", collapse = ", ")
              else "it runs until a condition changes"))
      } else {
        add(kind = "branch_candidate", where = statements[[i]]$where,
            via = "for", over = lp$over, collects = I(cl$collects),
            message = sprintf(paste0(
              "The for loop at %s over `%s` has independent iterations (it fills %s): ",
              "a candidate for dynamic branching."),
              statements[[i]]$where, lp$over,
              if (length(cl$collects)) paste0("`", cl$collects, "`", collapse = ", ")
              else "nothing kept"))
      }
    }
    if (length(st$applies)) {
      add(kind = "branch_candidate", where = statements[[i]]$where,
          via = st$applies[[1]], over = NA, collects = I(writes_of[[i]]),
          message = sprintf("`%s()` at %s applies a function to each element: a candidate for dynamic branching.",
                            st$applies[[1]], statements[[i]]$where))
    }
    flags <- unique(st$flags)
    msgs <- c(
      by_reference = "changes a data.table by reference (`:=`, `set*()`): the function must `data.table::copy()` its input first, or it changes the upstream Target's value in memory",
      global_assign = "assigns with `<<-`: a Target can't change another Target; return the value instead",
      assign = "creates a variable with `assign()`: name it explicitly so it can become a Target",
      options = "sets `options()`, which later code relies on: set it in the Pipeline script, before the Targets",
      Sys.setenv = "sets an environment variable, which later code relies on: set it in the Pipeline script, before the Targets",
      Sys.setlocale = "sets the locale for later code: set it in the Pipeline script, before the Targets",
      attach = "attaches data with `attach()`: pass the data as an argument instead",
      set.seed = "sets the seed: targets gives each Target its own seed, so later random draws differ (compared by structure). If it sits right before one random Step, call it inside that Step's function to keep the exact value",
      carried_reduce = "folds with `Reduce()`/`accumulate()`: each step feeds the next, so keep it inside one Target")
    for (f in intersect(flags, names(msgs)))
      add(kind = if (f == "carried_reduce") "carried_loop" else "global_state",
          flag = f, where = statements[[i]]$where,
          message = paste0(statements[[i]]$where, ": ", msgs[[f]], "."))
  }

  # 4. Names used before the statement that defines them.
  for (i in seq_len(n)) for (v in reads_of[[i]]) {
    if ("function_def" %in% statements[[i]]$st$flags) next
    w <- which(vapply(writes_of, function(x) v %in% x, TRUE))
    if (length(w) && all(w > i))
      add(kind = "defined_later", name = v, used_at = statements[[i]]$where,
          defined_at = statements[[w[[1]]]]$where,
          message = sprintf(paste0("`%s` is used at %s but first defined later, at %s: ",
            "an ordering problem in the Script Sequence (or a cycle). Flag it; don't reorder."),
            v, statements[[i]]$where, statements[[w[[1]]]]$where))
  }

  list(scripts = script_info, findings = findings,
       statements = lapply(seq_len(n), function(i) list(
         where = statements[[i]]$where, writes = I(writes_of[[i]]),
         reads = I(reads_of[[i]]),
         files_read = I(unique(statements[[i]]$st$files_read)),
         files_written = I(unique(statements[[i]]$st$files_written)))))
}

# ---------------------------------------------------------------------------
# Running the Script Sequence
# ---------------------------------------------------------------------------

# Runs in a fresh R session with the copy as working directory. Stubs are
# attached (not put in globalenv) so rm(list = ls()) can't remove them; they
# keep the script inside its copy and stop it installing anything.
run_scripts_session <- function(wd, specs, names, out) {
  setwd(wd)
  stubs <- new.env()
  stubs$setwd <- function(dir) invisible(getwd())
  stubs$install.packages <- function(...) invisible(NULL)
  stubs$View <- function(...) invisible(NULL)
  attach(stubs, name = "targetfy_stubs", warn.conflicts = FALSE)
  # Evaluate one top-level expression at a time, so a failure can be
  # reported with its script and line. A notebook's code runs from its own
  # folder, as knitting does.
  failure <- NULL
  for (sp in specs) {
    exprs <- tryCatch(parse(text = sp$code, keep.source = TRUE),
                      error = function(e) e)
    if (inherits(exprs, "error")) {
      failure <- list(script = sp$script, line = NA,
                      message = conditionMessage(exprs))
      break
    }
    refs <- attr(exprs, "srcref")
    base::setwd(file.path(wd, sp$wd))
    for (i in seq_along(exprs)) {
      msg <- tryCatch({ eval(exprs[[i]], globalenv()); NULL },
                      error = function(e) conditionMessage(e))
      if (!is.null(msg)) {
        k <- refs[[i]][[1]]
        failure <- list(script = sp$script, line = sp$src[[k]],
                        cell = sp$cell[[k]], where = sp$labels[[k]],
                        message = msg,
                        code = paste(as.character(refs[[i]]), collapse = "\n"))
        break
      }
    }
    base::setwd(wd)
    if (!is.null(failure)) break
  }
  present <- names[vapply(names, exists, logical(1), envir = globalenv(),
                          inherits = FALSE)]
  saveRDS(mget(present, envir = globalenv()), out)
  list(failure = failure, present = present)
}

# What each Source Script runs: its (tangled) code, where each line came
# from, and the folder it runs in.
script_specs <- function(wd, scripts) {
  lapply(scripts, function(s) {
    t <- tangle(file.path(wd, s))
    list(script = s, code = t$code, src = t$src, cell = t$cell,
         labels = vapply(seq_along(t$code), function(i) origin_label(s, t, i), ""),
         wd = if (t$notebook) notebook_wd(wd, s) else ".")
  })
}

run_scripts <- function(wd, scripts, names, out) {
  callr::r(run_scripts_session,
           args = list(wd, script_specs(wd, scripts), names, out))
}

# ---------------------------------------------------------------------------
# Running the Pipeline
# ---------------------------------------------------------------------------

with_wd <- function(dir, code) {
  old <- setwd(dir)
  on.exit(setwd(old))
  force(code)
}

# The store that goes with a Pipeline script: _targets.R uses _targets/,
# targets_<name>.R uses _targets_<name>/ so it never touches another store.
store_for <- function(pipeline) {
  if (pipeline == "_targets.R") "_targets"
  else paste0("_", tools::file_path_sans_ext(basename(pipeline)))
}

# The Step Map that goes with a Pipeline script: targetfy-map.json, or
# targetfy-map_<name>.json for targets_<name>.R.
map_for <- function(pipeline) {
  if (pipeline == "_targets.R") return("targetfy-map.json")
  name <- sub("^targets_", "", tools::file_path_sans_ext(basename(pipeline)))
  paste0("targetfy-map_", name, ".json")
}

static_check <- function(wd, pipeline = "_targets.R") {
  out <- list(parse_errors = list(), validate = NULL, manifest = NULL)
  r_files <- list.files(wd, pattern = "\\.[Rr]$", recursive = TRUE)
  for (f in r_files) {
    msg <- tryCatch({ parse(file.path(wd, f)); NULL },
                    error = function(e) conditionMessage(e))
    if (!is.null(msg)) out$parse_errors[[f]] <- msg
  }
  if (!file.exists(file.path(wd, pipeline))) {
    out$validate <- paste(pipeline, "not found")
    return(out)
  }
  with_wd(wd, {
    out$validate <- tryCatch({ targets::tar_validate(script = pipeline); "ok" },
                             error = function(e) conditionMessage(e))
    out$manifest <- tryCatch(
      as.data.frame(targets::tar_manifest(fields = c("name", "command"),
                                          script = pipeline)),
      error = function(e) conditionMessage(e)
    )
  })
  out
}

# Engines fitted by base R, and engines whose package has another name.
BASE_ENGINES <- c("lm", "glm", "nls", "")
ENGINE_PACKAGES <- list(stan = "rstanarm", spark = "sparklyr",
                        lightgbm = c("lightgbm", "bonsai"),
                        partykit = "partykit", h2o = c("h2o", "agua"),
                        keras = "keras", brulee = "brulee")

# Packages the code needs: library()/require()/requireNamespace() calls,
# set_engine("<pkg>"),
# pkg::fn, and tar_option_set(packages = ...). Read from the code, not run.
required_packages <- function(paths) {
  pkgs <- character()
  walk <- function(e) {
    if (!is.call(e)) return()
    fn <- e[[1]]
    fname <- if (is.symbol(fn)) as.character(fn) else ""
    if (is.call(fn) && identical(fn[[1]], quote(`::`)) ||
        is.call(fn) && identical(fn[[1]], quote(`:::`))) {
      pkgs <<- c(pkgs, as.character(fn[[2]]))   # pkg::fn(...)
      fname <- as.character(fn[[3]])
    }
    if (fname %in% c("::", ":::")) pkgs <<- c(pkgs, as.character(e[[2]]))
    if (fname %in% c("library", "require", "requireNamespace",
                     "loadNamespace") && length(e) > 1) {
      char_only <- isTRUE(tryCatch(eval(e$character.only, baseenv()),
                                   error = function(err) FALSE))
      arg <- e[[2]]
      if (is.character(arg) || (is.symbol(arg) && !char_only))
        pkgs <<- c(pkgs, as.character(arg))
    }
    # parsnip engines name the package that fits the model:
    # set_engine("glmnet") needs glmnet.
    if (fname == "set_engine" && length(e) > 1) {
      engine <- if (is.character(e[[2]])) e[[2]]
        else if (length(e) > 2 && is.character(e[[3]])) e[[3]]
      engine <- ENGINE_PACKAGES[[engine %||% ""]] %||% engine
      if (length(engine)) pkgs <<- c(pkgs, engine[!engine %in% BASE_ENGINES])
    }
    if (fname == "tar_option_set" && !is.null(e$packages)) {
      val <- tryCatch(eval(e$packages, baseenv()), error = function(err) NULL)
      if (is.character(val)) pkgs <<- c(pkgs, val)
    }
    # Index into the call: binding an empty argument (x[, 1]) to a
    # variable makes R treat it as missing.
    for (i in seq_along(e)[-1]) {
      if (!identical(e[[i]], quote(expr = ))) walk(e[[i]])
    }
  }
  for (p in paths[file.exists(paths)]) {
    exprs <- tryCatch(parse_code(p), error = function(e) NULL)
    for (e in exprs) walk(e)
  }
  sort(unique(pkgs[nzchar(pkgs)]))
}

missing_packages <- function(pkgs) {
  pkgs[!vapply(pkgs, function(p) nzchar(system.file(package = p)), TRUE)]
}

# The Generated Files and Source Scripts whose packages the check needs.
code_files <- function(dir, scripts, pipeline) {
  fun_files <- list.files(file.path(dir, c("R", "R_targets")),
                          pattern = "\\.[Rr]$", full.names = TRUE)
  c(file.path(dir, c(scripts, pipeline)), fun_files)
}

# TRUE when the Static Check failed only because a package isn't installed.
blocked_by_packages <- function(s) {
  length(s$parse_errors) == 0 &&
    any(grepl("there is no package called",
              c(s$validate, if (is.character(s$manifest)) s$manifest),
              fixed = TRUE))
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

# Targets still outdated after a full build, ignoring those whose cue
# always reruns them.
outdated_after_build <- function(wd, script, store) {
  with_wd(wd, tryCatch({
    out <- targets::tar_outdated(script = script, store = store,
                                 reporter = "silent")
    always <- tryCatch({
      m <- targets::tar_manifest(fields = c("name", "cue_mode"), script = script)
      m$name[m$cue_mode == "always"]
    }, error = function(e) character())
    setdiff(out, always)
  }, error = function(e) character()))
}

read_target <- function(wd, name, store = "_targets") {
  targets::tar_read_raw(name, store = file.path(wd, store))
}

# Rebuilds one Target (and what it depends on) in a separate store with a
# different global seed. Returns the new value, or an error condition.
rebuild_with_new_seed <- function(wd, name, pipeline = "_targets.R") {
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
    sprintf("source('%s', local = .targetfy_env)$value", pipeline)
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
load_globals <- function(wd, pipeline = "_targets.R") {
  tryCatch(callr::r(function(wd, pipeline) {
    setwd(wd)
    targets::tar_load_globals(envir = globalenv(), script = pipeline)
    objs <- mget(ls(globalenv(), all.names = TRUE), envir = globalenv())
    lapply(Filter(is.function, objs), body)
  }, args = list(wd, pipeline)), error = function(e) list())
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
                           keep = FALSE, pipeline = "_targets.R") {
  store <- store_for(pipeline)
  project <- normalizePath(project, winslash = "/", mustWork = TRUE)
  result <- list(mode = mode, pipeline = pipeline, store = store, status = NULL, static = NULL, targets = list(),
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

  result$missing_packages <- I(missing_packages(
    required_packages(code_files(project, scripts, pipeline))))
  result$static <- static_check(pipe_dir, pipeline)
  if (!static_ok(result$static) && blocked_by_packages(result$static)) {
    # Not a fault in the Conversion: the environment lacks a package, so
    # nothing could be checked. Never ask for fixes to the Generated Files.
    result$status <- "not_checked"
    result$equivalence <- "unverified"
    result$errors <- list(paste(
      "Not checked: these packages are not installed:",
      paste(result$missing_packages, collapse = ", ")))
    return(result)
  }
  if (mode == "static") {
    result$status <- if (static_ok(result$static)) "static_pass" else "static_fail"
    result$equivalence <- "unverified"
    return(result)
  }
  if (!static_ok(result$static)) {
    result$status <- "not_equivalent"
    result$errors <- list("Static Check failed")
    if (any(grepl("cycle", c(result$static$validate,
                             if (is.character(result$static$manifest)) result$static$manifest),
                  ignore.case = TRUE)))
      result$errors <- list(paste(
        "Static Check failed: the Pipeline's graph has a cycle. A Target depends,",
        "directly or not, on itself: give each version of a reassigned variable its",
        "own Target (see the flow scan's `reassigned` findings)."))
    return(result)
  }

  # 1. Run the Script Sequence in its own copy.
  target_map <- map$targets %||% list()
  step_names <- unique(unlist(target_map[!vapply(target_map, is.null, TRUE)]))
  script_dir <- copy_project(project, file.path(root, "script"), files)
  before <- file_hashes(script_dir)
  snapshot <- file.path(root, "script-objects.rds")
  run <- run_scripts(script_dir, scripts, as.character(step_names), snapshot)
  if (!is.null(run$failure)) {
    # The scripts fail on their own: no comparison is possible, so the
    # result falls back to the Static Check. Steps whose variable existed
    # when the scripts stopped were reached; the rest come after the failure.
    result$status <- "static_pass"
    result$equivalence <- "unverified"
    result$script_failure <- run$failure
    for (name in result$static$manifest$name) {
      step <- target_map[[name]]
      result$targets[[length(result$targets) + 1]] <- list(
        target = name, step = step %||% NA, result = "unverified",
        after_failure = if (is.null(step)) NA else !step %in% run$present)
    }
    return(result)
  }
  script_written <- written_files(before, file_hashes(script_dir))
  script_objects <- readRDS(snapshot)

  # 2. Build the Pipeline in its own copy.
  pipe_before <- file_hashes(pipe_dir)
  err <- build_pipeline(pipe_dir, script = pipeline, store = store)
  if (!is.null(err)) {
    result$status <- "error"
    result$errors <- list(paste("Pipeline failed:", err))
    return(result)
  }
  pipe_hashes <- file_hashes(pipe_dir)

  # A Pipeline must be up to date right after it's built. If it isn't, it
  # changed its own inputs (typically a file it reads and then overwrites),
  # and every tar_make() would run it again on its own output.
  result$outdated_after_build <- I(outdated_after_build(pipe_dir, pipeline, store))

  # 3. Compare Targets with their Steps.
  manifest <- result$static$manifest
  globals <- load_globals(pipe_dir, pipeline)
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
      value <- read_target(pipe_dir, name, store)
      expected <- script_objects[[step]]
      if (!entry$stochastic && values_match(value, expected)) {
        entry$result <- "match"
      } else {
        if (!entry$stochastic) {
          reseeded <- rebuild_with_new_seed(pipe_dir, name, pipeline)
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
  # A file the scripts overwrite in place is written by the Pipeline to
  # another path (`redirected_files`): compare the script's file there.
  handoff <- as.character(unlist(map$handoff_files))
  redirected <- map$redirected_files %||% list()
  for (f in script_written) {
    entry <- list(file = f)
    ext <- tolower(tools::file_ext(f))
    pf <- f
    if (!is.null(redirected[[f]])) {
      pf <- redirected[[f]]
      entry$redirected_to <- pf
    }
    if (f %in% handoff) {
      entry$result <- "handoff"
    } else if (!pf %in% names(pipe_hashes) ||
               (pf %in% names(pipe_before) &&
                  pipe_hashes[[pf]] == pipe_before[[pf]])) {
      entry$result <- "missing"
    } else if (pf != f && f %in% names(pipe_before) &&
               (!f %in% names(pipe_hashes) || pipe_hashes[[f]] != pipe_before[[f]])) {
      entry$result <- "mismatch"
      entry$detail <- sprintf("redirected to %s, but the Pipeline still changed %s", pf, f)
    } else if (pipe_hashes[[pf]] == tools::md5sum(file.path(script_dir, f))) {
      entry$result <- "match"
    } else if (ext %in% LOOSE_FILE_EXT &&
               file.size(file.path(pipe_dir, pf)) > 0) {
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
  if (length(result$outdated_after_build))
    result$errors <- c(result$errors, list(paste(
      "The Pipeline is out of date right after it was built:",
      paste(result$outdated_after_build, collapse = ", "),
      "- it changes its own inputs (a file it reads and then overwrites?).",
      "Write to another path and list it in the Step Map's redirected_files.")))
  result$status <- if (any(bad_targets) || any(bad_files) ||
                       length(result$outdated_after_build)) "not_equivalent"
    else "equivalent"
  result
}

EXIT_CODES <- c(equivalent = 0, static_pass = 0, not_checked = 0,
                not_equivalent = 1,
                static_fail = 1, error = 2, needs_confirmation = 3)

parse_args <- function(args) {
  opts <- list(pipeline = "_targets.R", mode = "equivalence", max_copy_mb = 1024, allow_large = FALSE,
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
  map_path <- opts$map %||% file.path(opts$project, map_for(opts$pipeline))
  map <- if (file.exists(map_path))
    jsonlite::read_json(map_path, simplifyVector = FALSE) else list()
  result <- tryCatch(
    targetfy_check(opts$project, opts$scripts, map, opts$mode,
                   opts$max_copy_mb, opts$allow_large, opts$keep,
                   opts$pipeline),
    error = function(e) list(status = "error", errors = list(conditionMessage(e)))
  )
  json <- jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE,
                           null = "null", na = "null", dataframe = "rows")
  if (is.null(opts$out)) cat(json, "\n") else writeLines(json, opts$out)
  quit(status = EXIT_CODES[[result$status]], save = "no")
}

if (sys.nframe() == 0L) main()
