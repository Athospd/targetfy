# targetfy v1: design decisions

Outcome of the 2026-11-21 grilling session. For vocabulary see [GLOSSARY.md](../GLOSSARY.md); for the reasoning behind the bigger decisions see [docs/adr/](adr/).

## What it is

A **Claude Code skill** (`/targetfy`) that turns a **Script Sequence** (one or more `.R` files the user lists) into an Equivalent `{targets}` Pipeline, then offers optional **Enhancements** through a step-by-step wizard.

- The AI model does the Conversion. A bundled R script (`Rscript`) is the authority that accepts or rejects it ([ADR 0001](adr/0001-llm-conversion-with-deterministic-check.md)).
- It bundles a pinned copy of targets-r-skill as the house style ([ADR 0002](adr/0002-vendor-targets-r-skill.md)).
- The tools it uses are Read, Grep, Glob, Write and Bash. An MCP server or R package waits until someone needs targetfy outside Claude Code.

## Hard rules

1. **targetfy never modifies any existing file.** It only writes Generated Files: `_targets.R`, `R_targets/` (or `R/`), and `targetfy-report.md`.
2. It refuses to proceed if `_targets.R` exists, and asks for an alternative folder if `R/` already contains files.
3. It never installs packages. If `renv.lock` exists, the check runs under it.
4. It never guesses which files belong to the analysis. The user lists the Script Sequence, and the order given is the order the scripts run.

## Conversion

- One Target per **Step**, meaning a meaningful object, not one per assignment. A chain of in-place modifications to the same variable becomes one Target.
- Logic goes into functions in `R_targets/`. `_targets.R` holds only short `tar_target(name, fn(deps))` calls and loads the functions with `tar_source()`.
- Each `library()` call becomes an entry in `tar_option_set(packages = ...)`. `pkg::fn` calls stay as they are.
- Input files are tracked with `tar_file_read()` and output files become file Targets.
- Lines that don't belong in a Pipeline (`setwd`, `rm(list = ls())`, `install.packages`, `View`, `readline`, `browser`, bare `print`/`head`) are dropped. Each is listed with its line number and the reason in the **Conversion Report**.
- **Handoff Files** (`saveRDS` → `readRDS` between scripts) become direct dependencies between Targets and are left out of the Equivalence comparison.
- **Sourced helpers**: a file that only defines functions is loaded in place via `tar_source()`. A file with top-level work is converted to Targets like any other code.
- A targets-r convention that can't be met produces a warning, not a failure.

### Unresolved Objects

Search order:
1. other `.R` files in the project;
2. `.RData` and `.rds` files with matching names;
3. installed packages (for names a user's `.Rprofile` may be providing).

The user is then offered the options that apply, with the best fit marked as the default:
- a. Add the defining file to the Script Sequence.
- b. Load a function-only file in place with `tar_source()`.
- c. Add a package.
- d. Track a data file with `tar_file_read()`.
- e. Wait for the user to fix the script.
- f. Assume the object exists. Only the Static Check runs, and the report says so.
- g. Abort.

Every choice is recorded in the report.

Ordering problems (a later script defines something an earlier one needs) are flagged, not fixed.

## Verification

- **Equivalence Check**: run the Script Sequence and the Pipeline in a temporary copy of the project, compare, then delete the copy.
  - The copy contains the code plus every file the scripts read, at the same relative paths. Files are copied, not symlinked (Windows often blocks symlinks).
  - If the copy would exceed about 1 GB, targetfy asks first. The user can copy anyway or fall back to the Static Check.
- **Comparing objects**: `all.equal()` between each Target's value and its Step's value at the end of the scripts.
- **Comparing files**: same content, except for file types that embed metadata (PDF, PNG, xlsx), where it's enough that the file exists and isn't empty. The report notes this.
- **Stochastic Targets**: a Target is marked stochastic if its code uses random functions, or if it fails the comparison and its value changes when built again with a different seed. Only its structure is compared (class, dimensions, column names). A mismatch whose value doesn't change with the seed is treated as a real bug.
- **Static Check** (when the scripts can't be run): the files parse, and `tar_validate()` and `tar_manifest()` pass. The result is marked "Equivalence unverified".
- **On failure**: fix the Generated Files and check again, up to 3 attempts. After that, stop and keep the Generated Files. The report names the failing Targets and what was tried.

### The check script (`scripts/check.R`)

```
Rscript scripts/check.R --project DIR --scripts a.R[,b.R] [--map map.json]
        [--mode equivalence|static] [--max-copy-mb 1024] [--allow-large]
        [--keep] [--out result.json]
```

- **Map**: the Conversion writes this file to tell the check which Step each Target replaces. Targets not listed in it are reported `not_compared`:
  ```json
  {"targets": {"sales_clean": "df", "model": "model"},
   "handoff_files": ["tmp/df.rds"],
   "stochastic": ["rf_fit"]}
  ```
- **Output**: JSON with a `status` per Target and per file written. The overall `status` and exit code are:
  - `equivalent` or `static_pass`: 0
  - `not_equivalent` or `static_fail`: 1
  - `error` (the Script Sequence or Pipeline failed to run): 2
  - `needs_confirmation` (the copy is over the size limit): 3
- **Script run**: the Script Sequence runs in a fresh R session. `setwd`, `install.packages` and `View` are replaced with no-ops, attached on the search path so that `rm(list = ls())` can't remove them.
- **Comparison**: before comparing, a model's stored `call`, environments and formula environments are removed. These always differ once code is wrapped in functions.
- **Reseed rebuild**: the Target is rebuilt in a separate store, with the seed set *before* the Targets are defined. targets fixes each Target's seed when it is defined.

## Enhancement wizard

Runs after a passing Conversion. It suggests Enhancements tied to specific Targets, and the user accepts or declines each one. Each accepted Enhancement re-runs the check and is undone if the check fails.

v1 catalog:
1. **Storage format**: `tar_qs()` for big objects, `tar_parquet()` for big data frames.
2. **Dynamic branching**: `pattern = map(...)` in place of `for`, `lapply` or `purrr::map` loops over groups or files.
3. **Parallel workers**: `{crew}` workers, offered only once branching or independent Targets make it worthwhile.

## Out of scope for v1 (planned)

- Stricter comparison levels, for example with `{waldo}`.
- `.Rmd`, `.qmd` and `.ipynb` (R kernel) as **analysis notebooks**: the code chunks or cells become the Source Script and the prose is dropped.
- A **report** Enhancement: a new copy of the notebook reads results with `tar_read()` and is rendered with `tar_quarto()`.
- SQL and other external sources, and HPC or cloud storage, as Enhancements.
- `.py` scripts via `{reticulate}`.

## Refused

`.Rnw`, R files inside a package, Shiny apps. These aren't linear analyses, so targetfy refuses them with a clear message.
