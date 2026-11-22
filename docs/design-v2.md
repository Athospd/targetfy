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

## The Invalidation Check

One comparison run can't tell a tracked input from an untracked one: both sides read the same bytes. A Pipeline whose function reads `data/rates.csv` itself passes, then goes stale the first time the file changes. This was suggested in a reply to the launch post.

- **Procedure**, after the plain comparison passes. For each input file:
  1. change it in fresh copies;
  2. rerun the Script Sequence and note which Steps change;
  3. in a copy of the built Pipeline, ask `tar_outdated()`, then rebuild.
- **Verdicts** per mapped Target:
  - `hidden_dependency`: the Step changed but the Target wasn't outdated. Fails the check.
  - `mismatch_after_change`: the Target reran but no longer matches. Fails the check.
  - `extra_rerun`: the Target reran but its Step didn't change. Informational.
  - `reran` and `unaffected`: as expected.
  - Stochastic Targets are skipped.
- **Inputs, most likely first:** files the code reads by name, files the Pipeline tracks, then every other data file in the project. The last group catches reads the scan can't see, such as computed paths, helpers and package code. At most `--max-inputs` (10) are tested, and the rest are listed.
- **The change:** a small, valid edit that keeps the format. CSV, TSV, TXT and DAT files get their last data line repeated; for `.rds`, a data frame gets its last row repeated and a vector its last element. Anything else is `not_tested`, and the report says so.
- **Cost:** one more script run and one Pipeline rebuild per input. `--skip-invalidation` turns it off.
- **Scan side:** new `hidden_input` findings for readers with computed paths and for session reads (`Sys.getenv()`, `Sys.Date()`, `Sys.time()`, `getOption()`, file times), to be made explicit Targets (`cue = tar_cue("always")` where they must be read every run). `outdated_after_build` now exempts the Targets downstream of always-run and tolerated Targets.
- **Not covered:** inputs that aren't files (databases, APIs). An input whose small change the scripts happen to ignore (deduplication, for example) shows as `unused` or `extra_rerun`, never as a false failure.

## More targets and tarchetypes tools

An internal review of the Enhancements found two correctness holes and several unused built-in tools.

- **Correctness, handled during the Conversion:**
  - objects that break as RDS (`torch`, `keras`, h2o models; connections) get a `tar_format()` or stay inside a function;
  - web inputs get `format = "url"` or `tar_download()`.
  - The scan flags them as `unsaveable_object` and `hidden_input: url`. URLs no longer count as file reads.
- **The branching style:** each `branch_candidate` now carries a `style` that picks the tool. All three new recipes are equivalent in fixture `branch_styles`:
  - `static`: a short literal list → `tar_map()` + `tar_combine()`. `tar_combine()` names the pieces `fit_1`..., so restore the script's names.
  - `groups`: `split()`/`group_map()` → `tar_group_by()` + `pattern = map()`.
  - `replicate`: `replicate()` or random draws over `1:n` → `tar_rep()` in batches. `tar_rep()` names each repetition, so `unname()` it.
  - `dynamic`: everything else.
- **A `_targets.yaml` project** for `targets_<name>.R`, created with `tar_config_set()` only when the file doesn't exist. `TAR_PROJECT` then replaces passing `script =` and `store =`. A test checks that the `main` project and the check are unaffected.
- **Report tips:** `tar_watch()`/`tar_poll()`, `workspace_on_error` + `tar_workspace()`, `tar_outdated()`.
- **Not verified here:** the torch and keras formats (neither package is installed), `format = "url"` and `tar_download()` (no network fixture).
- **Deferred to v2.1:** `tar_render_rep()`/`tar_quarto_rep()`, `tar_change()`/`tar_age()`, `tar_renv()`, `tar_github_actions()`.

## Tested against a real targets repository

[targets-live](https://github.com/Athospd/targets-live), a teaching repository, has:
- a 492-line tidymodels `.Rmd` tuned in five steps;
- `.qmd` reports that call `tar_read()`;
- three Pipeline scripts;
- a `_targets.yaml` that points `main` at `_targets_parallel.R`.

Running the scan and the check on it found and fixed:

| Found | Fix |
|---|---|
| chunk headers like `{r, fig.height=12}` gave the options as the label | the label is the first option only when it has no `=` |
| each reassigned variable was reported once; `telco_model` actually has 6 versions | `versions` and `version_starts` list them all |
| `cache = TRUE` chunks weren't mentioned | a notebook warning: these Steps are the first candidates for their own Targets |
| the notebook stopped at line 78, a console leftover (`step_corr()` with no recipe), so nothing could be compared; rendering fails there too | a failing display-only statement is skipped and reported (`display_errors`); a statement that assigns, writes, attaches or asserts is never skipped |
| `plot()` in a non-interactive run writes `Rplots.pdf`, which counted as a file the scripts wrote | plots go to a null device during the script run |
| the `.qmd` reports and `_targets_parallel.R` were treated as analyses | `already_targets` findings, with a `targets_role` of `pipeline`, `driver` or `report`; preflight stops on them |
| 43 display-only lines in the notebook | `display_only` findings, per script |

The existing `_targets.yaml` redirect didn't affect the check, since every call passes `script` and `store` explicitly. The offline fixture `realworld` reproduces these patterns without the network or tidymodels.

## Still out of scope

- A granularity setting for Targets.
- `{waldo}`-level comparison.
- SQL, HPC and cloud storage as Enhancements.
- `.py` via `{reticulate}`.
- Python cells (`%%R` magics) in Python notebooks.
