# The Pipeline script's setup: `tar_source()`, `tar_option_set()` and what comes before `list()`

Some of a script's code isn't a Step: it defines functions, loads helpers, or changes the session for the code after it. In a Pipeline it belongs in the setup, the part of the Pipeline script above `list(...)`. `read.json` finds it: `script_function`, `sourced_file` and `sourced_folder` findings, plus `pipeline_setup` findings, each with a `setup` kind and usually a `suggest`ed line. Record each one in the report's **Script flow** section.

The setup is written in this order:

```r
library(targets)
library(tarchetypes)
pkgload::load_all("mypkg", quiet = TRUE)          # dev_package only

tar_source(c("R", "helpers.R", "utils"))          # functions
tar_option_set(
  packages = c("dplyr", "mypkg"),
  imports = "mypkg",                              # local or dev package, if the user agrees
  seed = 42,                                      # top-level set.seed(42)
  memory = "transient", garbage_collection = TRUE # rm()/gc() between Steps
)
options(contrasts = c("contr.sum", "contr.poly")) # global_options

list(...)
```

## Functions: `tar_source()`

| Finding | What to do |
|---|---|
| `script_function`: `f <- function(...)` in a Source Script | Copy it verbatim into `<script>_functions.R`, and have Steps call it. Don't rewrite it. targets tracks its body, so an edit reruns the Targets that use it. |
| `sourced_file` with `functions_only: true` | Load it where it is: add its path to `tar_source()`. Don't copy it, so the user's edits to it still count. |
| `sourced_file` with `functions_only: false` (it reads data, sets options, computes) | Convert it like a Source Script: its functions go into `<file>_functions.R`, and its work becomes Targets. Never `tar_source()` it, since its work would run every time the Pipeline script is read. Ask the user where it sits in the Script Sequence (`references/unresolved-objects.md`, option a). |
| `sourced_folder`: `lapply(list.files("utils", ...), source)`, or a `for` loop | Every file only defines functions: add the folder to `tar_source()`. Otherwise, add the function-only files one by one, and treat the others as above. |

`tar_source()` loads every `.R` file in a folder, so never add a folder that also holds Source Scripts.

## Session changes

| `setup` | What to do |
|---|---|
| `global_options`: `options()`, `Sys.setenv()`, `Sys.setlocale()` | Put the line in the Pipeline script after `tar_option_set()`, before `list()`. targets runs the Targets in the session that reads the Pipeline script, so the setting holds. If the parallel-workers Enhancement is added later, workers don't read those lines: wrap the Target list in `tarchetypes::tar_hook_before(hook = <the line>, list(...))` too. |
| `seed`, at top level: `set.seed(42)` | Set `tar_option_set(seed = 42)`. targets gives each Target its own stream derived from it, so random results are reproducible, but they differ from the script's and are compared by structure. If the `set.seed()` sits right before the only random Step, with nothing random in between, put `set.seed(42)` at the top of that Step's function instead: the value then matches the script exactly. |
| `seed`, inside other code | Keep it in the same function as the draws it governs. |
| `memory`: `rm(x)`, `gc()` | Drop the lines (list them under "Lines left out"), and set `memory = "transient", garbage_collection = TRUE`. `rm(list = ls())` is still dropped as before, with nothing added. |
| `tolerated_error`: a whole statement wrapped in `try()`/`tryCatch()` | If it returns a fallback value (`x <- tryCatch(f(), error = function(e) NA)`), keep the `tryCatch()` inside the function. If the script simply carries on without the result (`try(x <- f())`), give that Target `error = "null"`. The check reports it under `tolerated_errors`, not as a failure. Don't set `error = "null"` or `"continue"` for the whole Pipeline. |
| `environment_setup`: `.libPaths()`, `renv::activate()`, `source("renv/activate.R")` | Not part of the analysis: the library belongs in the project's `.Rprofile`, where renv puts it. Drop the line and list it. If `.Rprofile` doesn't set it up, tell the user that the Pipeline expects the same library. |

## Packages: `packages` and `imports`

- `packages`: every package the scripts attach with `library()` or `require()`. A package used only as `pkg::fn()` or behind `requireNamespace()` isn't attached, so it stays out.
- `imports` makes targets track a package's functions as if they were the project's own: editing one reruns the Targets that use it. It's useful only for packages the user writes.
  - `local_package` (installed from local source, with no repository or remote): ask the user whether to add `imports = "<pkg>"`, and recommend it.
  - `dev_package` (`pkgload::load_all("mypkg")` / `devtools::load_all()`): put `pkgload::load_all("<path>", quiet = TRUE)` at the top of the Pipeline script, and set `imports = "<package name>"` (the `Package:` field of its `DESCRIPTION`, not the folder). Don't add it to `packages`, because it isn't installed.
- `format`: never during a Conversion. When the storage-format Enhancement applies the same format to most Targets, set it once as `tar_option_set(format = "qs")` instead of per Target (`references/enhancements.md`).
