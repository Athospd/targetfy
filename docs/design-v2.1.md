# targetfy v2.1: design notes

v2.1 adds the tools deferred from v2 and tests the paths v2 couldn't run.

## Rendering from a script: `render_call`

A Source Script that calls `rmarkdown::render()` or `quarto::quarto_render()` builds a document. The flow scan reports a `render_call` finding, with:
- `suggest`: `tar_render()`, `tar_quarto()`, or their `_rep` variants when the render runs in a loop with `params`;
- a `branch_candidate` with `style: render_rep` for that loop.

This is converted during the Conversion, not offered as an Enhancement, because a render inside a plain Target hides the document's dependencies. The user's document is never edited: a copy reads Targets with `tar_read()`. Tested in the `render_rep` fixture: three reports, equivalent, and changing the data reruns them.

Found while testing: `tar_render_rep(report, ...)` creates a Target named `report_params`, so a helper function of that name conflicts with it.

## Data targets can't see change: `tar_change()` / `tar_age()`

Database and API reads (`dbGetQuery()`, `dbReadTable()`, `req_perform()`, `GET()`, `bq_table_download()`...) are reported as `hidden_input` with `input: "external"`. The advice is:
- `tar_change()` with a cheap check (a row count, `max(updated_at)`);
- or `tar_age()` when no cheap check exists.

The Invalidation Check now changes local SQLite files (`.sqlite`, `.sqlite3`, `.db`) by repeating the last row of each table. That makes `tar_change()` testable, as in the `external` fixture:
- with `tar_change()`: equivalent, and changing the database passes;
- with a plain Target: a hidden dependency. The error names `tar_change()` for database files.

## renv: `tar_renv()`

When the project has an `renv.lock`, `result.json` gets `renv`: the packages the Pipeline uses (`library()`, `pkg::`, `tar_option_set(packages = ...)`, per-Target `packages`) and those the lockfile doesn't record. renv's own scan misses packages named as strings. The Enhancement runs `tar_renv(extras = character(0))`. The user runs `renv::snapshot()`, since `renv.lock` is theirs.

## GitHub Actions: `tar_github_actions()`

An Enhancement for git repositories with a GitHub remote that use renv. It can't be checked locally, so the report says it's untested until pushed.

## Paths v2 couldn't run, now tested

| Path | Result |
|---|---|
| torch `tar_format()` | with the format: equivalent; with plain RDS, the Pipeline passes while the model stays in memory and fails with "external pointer is not valid" once it's read back (`memory = "transient"`) |
| `format = "url"` | equivalent against a real URL, not outdated after the build. Web inputs are now listed under `invalidation.web_inputs` |
| crew workers | with `tar_hook_before()`: equivalent. With `options()` only above `list()`: `fit`, `coefs` and `label` mismatch, since workers never run that line. Needs targets ≥ 1.9 with crew 1.3: targets 1.8.0 expects a `worker` column crew 1.3.3's summary no longer has |
| keras `tar_format()` | with `keras_format` (through a temporary `.keras` file): equivalent; with plain RDS, `pred` fails with "object is from previous session and is now invalid". Tested with keras3 1.5.1, Keras 3.15.1 and TensorFlow 2.21.0, in an `r-keras` virtualenv on Python 3.11.9. On Windows, build that virtualenv from a python.org (or winget) Python, never a Microsoft Store one: R can't load a Store Python's DLL ("Access is denied"), and reticulate may pick it on its own |
| `tar_quarto_rep()` | equivalent to a `quarto_render()` loop (Quarto 1.11.9). Found two things: the document copy must pass its store to `tar_read()` (`store = "_targets_<name>"`), or it fails on the default `_targets/`; and Quarto's `<document>_files/` support folder, named after the document, now counts as support files, not results |

## Smaller fixes

- `obj$method()` calls (`knitr::opts_chunk$set()`, R6 objects) are never display-only.
- A build failure names each Target that errored, with its message (`failed_targets`), instead of `tar_make()`'s generic advice.
