# targetfy v2: design decisions

v2 adds three things on top of [v1](design-v1.md): scripts that aren't DAGs, notebooks as Source Scripts, and a dynamic-branching Enhancement tested end to end. Vocabulary is in [GLOSSARY.md](../GLOSSARY.md).

## Scripts that aren't DAGs

A script is a sequence. Mapping one variable to one Target turns several common patterns into a cycle, or into a Pipeline that's never up to date:

| Pattern | Example | What the Conversion does |
|---|---|---|
| a **Version**: a variable changed after another Step used it | `model <- lm(..., sales)`, then `sales$pred <- predict(model, sales)` | one Target per Version (`sales_raw` → `model` → `sales`); only the last maps to `sales` |
| an **In-place File** | read `data/sales.csv`, later `write.csv(..., "data/sales.csv")` | asks the user; the default writes a Redirected File (`data/sales_targetfy.csv`) |
| a **Carried Loop** | `for (i in 1:20) x <- x / 2 + 1 / x`, `while`, `Reduce()` | the whole loop stays inside one Target |
| global state | `<<-`, `assign()`, `options()`, data.table `:=`, `set.seed()` | per-flag rules in `references/flow.md` |
| used before defined | a name assigned only in a later script | flagged as an ordering problem, never reordered |

Decisions:

- **A deterministic Flow Scan, not judgement alone.** `scripts/read.R` parses the code (it runs nothing). For every top-level statement it records the names read and written and the literal file paths read and written. From that it reports `reassigned` (with `cycle: true` when the later Version reads what was built from the earlier one), `in_place_file`, `handoff`, `carried_loop`, `branch_candidate`, `global_state` and `defined_later`. The model still does the Conversion, but it starts from a list of the traps.
- **Loop classification.** A `for` loop is independent when every variable it changes is local to the iteration (assigned from scratch earlier in the same iteration), or a collection filled at a position derived from the loop variable (`fits[[region]]` where `region` comes from `f`), or appended to (`res <- c(res, ...)`). Anything that reads its own previous value carries state. `while`, `repeat`, `Reduce()` and `accumulate()` always carry state.
- **Two new check guarantees.**
  - A Pipeline whose graph has a cycle fails the Static Check with a hint pointing at Versions.
  - After the build, `tar_outdated()` must be empty (ignoring Targets whose cue is `always`). If it isn't, the Pipeline changes its own inputs, and the result is `not_equivalent` with `outdated_after_build`. This catches an In-place File converted naively, which a single comparison run would miss.
- **Redirected Files in the Step Map.** `"redirected_files": {"data/sales.csv": "data/sales_targetfy.csv"}` makes the check compare the script's file with the Pipeline's file at the new path, and fail if the Pipeline still changed the original.

## Notebooks

`.qmd`, `.Rmd`, `.md` and R-kernel `.ipynb` are Source Scripts. Their R code, in order, is the analysis.

- **Extraction lives in `check.R`** (`tangle()`), so the check, `find-r.R` (package detection) and `read.R` agree on what the code is. `read.R --tangle-dir` writes it as `.R` for the model to read, each chunk headed by its notebook line.
- **What counts as code** follows what rendering would run:
  - in `.qmd`/`.Rmd`, braced ```` ```{r} ```` chunks only (```` ```r ```` is display);
  - in `.md`, both kinds;
  - `eval = FALSE` / `#| eval: false` chunks and other languages are skipped and reported;
  - YAML `params` become `params <- list(...)` first, read with `knitr::knit_params()`;
  - inline code is reported, not run.
- **Line mapping.** Failures and findings are reported in the notebook's own coordinates (`report.qmd:42`, `nb.ipynb:cell 3, line 2`), through `script_failure.where`.
- **Working directory.** The check runs a notebook from its own folder, as knitr and Quarto do: from the project folder only when a `_quarto.yml` says `execute-dir: project`. The Pipeline runs from the project folder, so the Conversion rewrites relative paths.
- **Refused:** notebooks with a non-R kernel. `.Rnw` is still refused.
- **Render the document** is an Enhancement, not part of the Conversion. A new copy of the notebook (`<name>_targets.qmd`/`.Rmd`) reads results with `tar_read()` and is rendered by `tar_quarto()`/`tar_render()`. The original notebook is never touched. The check builds the document, so a render failure fails the check, and reports it `not_compared`. It was tested with `tar_render()`; `tar_quarto()` needs Quarto on the PATH, which the test machine didn't have.

## Dynamic branching, tested

The example is `tests/fixtures/branching/`: a `for` loop fits one `lm()` per region file, followed by a summary table and a per-region forecast.

1. The Flow Scan reports the loop as a `branch_candidate` that fills `fits`.
2. Conversion: one Target per Step, with the loop inside `fit_region_trends()`, and `tar_files_input()` for the files.
   - Check run 1 failed: the `tar_files_input()` Target's value is a named vector, the script's `files` isn't.
   - Rule added: file-tracking Targets are never mapped.
   - Run 2: equivalent.
3. Enhancement: the loop body becomes `fit_region_trend(region_file)`, branched with `pattern = map(region_files), iteration = "list"`, and the forecast branches over `region_fit`. The check stayed equivalent.
4. The pitfall: a combined list is named after its branches (`region_fit_3f2a...`). The per-element function returns `setNames(list(fit), region)`, and a combining Target, `do.call(c, unname(region_fit))`, rebuilds the script's `fits`. Without it, the check fails.
5. Incremental behaviour: after editing one region file and adding a fifth, only those two branches (and what depends on them) rebuilt. The rest were skipped.

These lessons are in `references/enhancements.md`.

## The Pipeline Setup: `tar_source()` and `tar_option_set()`

Code that isn't a Step goes into the Pipeline Setup, the part of the Pipeline script above `list()`. The Flow Scan finds it, and `references/setup.md` holds the rules:

| Script code | Pipeline Setup | How it was verified |
|---|---|---|
| `f <- function(...)` in a Source Script | copied verbatim into the functions file | fixture `setup` |
| `source("helpers.R")` of a function-only file | `tar_source(c("R", "helpers.R"))`, loaded in place | fixture `setup` |
| `source()` of a file that also does work | converted like a Source Script, never `tar_source()`d | scan test |
| `lapply(list.files("utils", ...), source)` | `tar_source(c("R", "utils"))` | fixture `setup` |
| `options()`, `Sys.setenv()`, `Sys.setlocale()` | the same line before `list()`; with workers, also `tar_hook_before()` | equivalent both ways; a Pipeline without it fails the check (`contrasts` changes the coefficients) |
| top-level `set.seed(42)` | `tar_option_set(seed = 42)`, or `set.seed()` inside the function when it sits right before the only random Step | the in-function form matches exactly |
| `rm(x)`, `gc()` | dropped, plus `memory = "transient", garbage_collection = TRUE` | fixture `setup` |
| `try(x <- f())` | `error = "null"` on that Target | the check reports it under `tolerated_errors` |
| `.libPaths()`, `renv::activate()` | dropped: it belongs in `.Rprofile` | scan test |
| `pkgload::load_all("pkg")`, a locally installed package | `load_all()` at the top, `imports = "<package>"` | fixture `devpkg`; editing the package's function made the Target outdated |

Check changes this needed:
- **An exact match wins.** A Target with random calls whose value matches the script exactly is reported `match`, while still marked stochastic. It used to be compared by structure only.
- **Tolerated errors.** Targets declared with `error = "null"` may fail without failing the build, and they're left out of `outdated_after_build`.
- **The manifest** now includes each Target's `error` mode.

Not verified: `tar_hook_before()` on real crew workers, since `crew` isn't installed on the test machine. The hook itself was tested on a sequential Pipeline.

## Still out of scope

- A granularity setting for Targets.
- `{waldo}`-level comparison.
- SQL, HPC and cloud storage as Enhancements.
- `.py` via `{reticulate}`.
- Python cells (`%%R` magics) in Python notebooks.
