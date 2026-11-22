# Enhancement wizard

An **Enhancement** is an optional change to a Pipeline that already passes the check. Offer them **one at a time**. Each suggestion is tied to specific Targets and says why, for example: "`fit_by_region` loops over 12 regions. Switch it to dynamic branching so each region caches separately?"

## The loop, for each accepted Enhancement

1. Save a copy of every Generated File you're about to change.
2. Apply the Enhancement, following the house style in `vendor/targets-r-skill/`.
3. Run the check with the same mode as the Conversion.
4. If the status differs from the Conversion's (for example, it was `equivalent` and is now `not_equivalent`), restore the saved copies and tell the user why the Enhancement was undone.
5. Record it in the report's Enhancements section: what was offered, the user's answer, and the check result.

Offer only the Enhancements whose condition holds, in this order:

| Enhancement | Offer it when | How | House-style reference |
|---|---|---|---|
| Storage format | a Target holds a large R object, or a large data frame | `tar_qs()` (needs `qs2`), `tar_parquet()` (needs `arrow`), `tar_nanoparquet()`; when most Targets take the same format, set it once with `tar_option_set(format = "qs")` | `vendor/targets-r-skill/references/targets.md` |
| Branching | a `branch_candidate` finding: a Step loops over files, groups, parameters or repetitions | by its `style`: `dynamic` → `pattern = map(...)`; `static` → `tar_map()`; `groups` → `tar_group_by()`; `replicate` → `tar_rep()` (below) | `vendor/targets-r-skill/references/branching.md` |
| Parallel workers | branching or independent Targets mean several can run at once | `tar_option_set(controller = crew::crew_controller_local(workers = n))`; any `options()`/`Sys.setenv()` line in the setup must also go into `tar_hook_before()`, because workers don't run it (`references/setup.md`) | `vendor/targets-r-skill/references/performance.md` |
| Render the document | a Source Script is a `.qmd` or `.Rmd` the user renders | a new copy of the notebook reads results with `tar_read()`, rendered by `tar_quarto()` or `tar_render()` (see below) | `vendor/targets-r-skill/references/literate.md` |
| Record packages in renv | `result.json` has `renv.missing`: the project has an `renv.lock` that doesn't record every package the Pipeline uses | `targets::tar_renv()` writes `_targets_packages.R` with a `library()` call per package, so renv finds them (see below) | |
| Run on GitHub | the project is a git repository with a GitHub remote, and uses renv | `targets::tar_github_actions()` writes `.github/workflows/targets.yaml` (see below) | |

If an Enhancement needs a package that isn't installed, offer it only together with the instruction to install that package: the user installs it, never targetfy.

## Record packages in renv

renv finds a project's packages by scanning its code for `library()` calls and `pkg::`. It doesn't see packages named as strings, as in `tar_option_set(packages = "dplyr")`, so `renv::snapshot()` can leave them out of `renv.lock`, and the Pipeline then fails on another machine.

1. Run `Rscript -e 'targets::tar_renv(script = "<Pipeline script>", extras = character(0))'` from the project. By default `tar_renv()` also lists packages for targets' own tools (`visNetwork`, `shiny`, `crew`...); add them back only if the user wants those tools recorded. It writes `_targets_packages.R`, a new file. If that file already exists, ask before replacing it.
2. Don't run `renv::snapshot()`: it changes `renv.lock`, the user's file. Tell the user to run it, and list `renv.missing`.
3. Packages that aren't installed can't be recorded: name them for the user to install first (`renv::install()`).

## Run on GitHub

`targets::tar_github_actions()` writes `.github/workflows/targets.yaml`. On every push, GitHub restores the renv library, runs `tar_make()`, and keeps the store on a `targets-runs` branch, so later runs skip up-to-date Targets.

- Offer it only with renv (the workflow restores packages from `renv.lock`), after the renv Enhancement if `renv.missing` isn't empty.
- If `.github/workflows/targets.yaml` exists, don't offer it.
- For a `targets_<name>.R` Pipeline, the workflow runs the project's default script: add `script` to its `tar_make()` call, or rely on the `_targets.yaml` project and set `TAR_PROJECT` in the workflow's `env:`.
- Data files the Pipeline reads must be in the repository, and secrets (database passwords, API keys) go in the repository's GitHub secrets, never in the workflow file.
- The check can't run GitHub: say the workflow is untested until the user pushes it, and tell them where to watch the run (the repository's Actions tab).

## Branching

Each `branch_candidate` finding has a `style` that picks the tool. Follow that recipe, then the common rules (*Dynamic branching* below, steps 4–6: rebuild the script's object under its old name, and map only that).

| `style` | The script | The Pipeline | Rebuilding the script's object |
|---|---|---|---|
| `dynamic` | a loop or `lapply()` over files or a computed vector | `pattern = map(<values Target>)` | see below |
| `static` | a loop over a short literal list: `for (deg in c(1, 2, 3))` | `fit_by_degree <- tar_map(values = list(deg = degrees), tar_target(fit, fit_poly(d, deg)))`, defined above `list()` | `tar_combine(fits, fit_by_degree, command = setNames(list(!!!.x), as.character(degrees)))`: the combined Targets are named `fit_1`, `fit_2`..., so restore the script's names |
| `groups` | `lapply(split(d, d$g), f)`, `group_map()` | `tar_group_by(groups, d, g)` (needs `dplyr`), then `tar_target(x, f_one(groups), pattern = map(groups), iteration = "list")` | the per-group function returns `setNames(list(value), part$g[[1]])`; combine with `do.call(c, unname(x))`. Groups come out sorted, as `split()` sorts them |
| `render_rep` | a loop rendering a document with `params` | `tar_render_rep()` / `tar_quarto_rep()`, done during the Conversion (`references/flow.md`, `render_call`) | the rendered files keep the script's names through the `output_file` column |
| `replicate` | `replicate(100, mean(rnorm(20)))`, or a loop over `1:n` drawing random numbers | `tar_rep(sims_reps, mean(rnorm(20)), batches = 4, reps = 25)`: batches, not one branch per repetition | `tar_target(sims, unname(sims_reps))`: `tar_rep()` names every repetition. The values are random, so they're compared by structure |

Prefer `static` only when the values are few, known in advance and worth reading in the graph (models, scenarios). For a list computed from data, use `dynamic`. For more than a few hundred iterations, batch them: `tar_rep()` for repetitions, or a `pattern = map()` over chunks of the input.

## Dynamic branching

Offer it for `read.json`'s `branch_candidate` findings, and only when each iteration does real work: reading a file, fitting a model, a simulation. A `vapply()` that pulls one number from each model isn't worth a branch.

1. **What to iterate over:** an upstream Target holding the values.
   - For files, use `tarchetypes::tar_files_input(region_files, list.files("data/regions", pattern = "\\.csv$", full.names = TRUE))`. Each file is tracked, and a new file is picked up whenever the Pipeline runs. Don't use a plain `tar_target(files, list.files(...))`: it doesn't see files change.
   - For groups, use a Target holding the groups (`split()`, `dplyr::group_by() + tar_group()`).
   - For parameters, use a Target holding the parameter vector or table.
2. **One iteration per function:** turn the loop body into a function of one element, for example `fit_region_trend(region_file)`.
3. **The branch Target:** `tar_target(region_fit, fit_region_trend(region_files), pattern = map(region_files), iteration = "list")`. Use `iteration = "list"` for models and other non-vector objects. The default `"vector"` row-binds data frames, which suits per-group tables.
4. **Rebuild the script's object** in a separate Target that keeps the old name (`fits`), so everything downstream and the Step Map stay the same.
   - A combined list is named after the branches (`region_fit_3f2a9c...`), not after what the script used (`fits[[region]]`). Have the per-element function return `setNames(list(value), key)`, and combine with `do.call(c, unname(region_fit))`.
   - Row-bound data frames come out in branch order, which is the order of the input Target (`list.files()` order for files).
5. **Downstream branching:** a per-element step after the loop (a forecast per region) can map over the branch Target too: `pattern = map(region_fit)`.
6. **The Step Map:** the branch Target itself (`region_fit`) isn't mapped. The combining Target maps to the script's variable. File-tracking Targets (`region_files`, `region_files_files`) are never mapped either: their values are named paths.

Then run the check. If it fails with `names for target but not for current`, the combining step kept the branch names.

## Render the document

Offer it after the Conversion of a `.qmd` or `.Rmd` the user renders. It needs Quarto on the PATH for `.qmd` (`quarto::quarto_path()` isn't `NULL`), or pandoc for `.Rmd` (`rmarkdown::pandoc_available()`). If the tool isn't available, offer it together with the instruction to install it.

1. Write a new Generated File next to the notebook: `<name>_targets.qmd` (or `.Rmd`). Copy the notebook's prose, YAML and chunk options, and replace each chunk's computations with `targets::tar_read(<target>)` (or `tar_load()`) of the Targets that replaced them. Keep the chunks that only display results (plots, tables, printing), now reading the Targets. Never modify the original notebook.
2. For a Pipeline other than `_targets.R`, pass its store: `targets::tar_read(total, store = "_targets_<name>")`.
3. Add `tar_quarto(report, "<name>_targets.qmd")` or `tar_render(report, "<name>_targets.Rmd")` to the Pipeline. Both find the `tar_read()` calls and depend on those Targets.
4. Run the check. It builds the document. The document Target is reported `not_compared`, since the scripts never rendered it, and a render failure is a Pipeline build `error`.
5. If the notebook used `params`, keep its YAML `params:` and read the `params` Target only where the computations moved.
