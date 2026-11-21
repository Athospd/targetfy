# Conversion rules

The house style is the bundled targets-r skill: `vendor/targets-r-skill/SKILL.md` and its `references/targets.md`. Read both before writing. Where they conflict with this file, this file wins.

## Steps: what becomes a Target

A **Step** is a meaningful object the scripts build: a dataset, model, summary, plot or written file. Each Step becomes one Target. A Step is not an assignment:

```r
df <- read.csv("data/sales.csv")   # ┐
df <- df[df$year > 2020, ]          # ├ Step `sales_clean` (plus a tracked input)
df$rev <- log(df$rev)               # ┘
model <- lm(rev ~ region, df)       # Step `model`
coefs <- summary(model)$coefficients  # Step `model_summary`
```

- Statements that keep modifying the same object form one Step.
- A new object that something downstream uses, or that the user would want to inspect, starts a new Step.
- Name Targets as nouns that describe the content (`sales_clean`, not `df2`). Name functions as verbs (`clean_sales()`).

## Code layout

- Put each Step's logic in a function in the functions folder (`R/` or `R_targets/`). Pass data in as arguments, never through globals.
- `_targets.R` holds only `library(targets)`, `library(tarchetypes)`, `tar_source("<functions folder>")`, `tar_option_set(packages = ...)` and short Target calls like `tar_target(name, fn(dep1, dep2))`. Always pass the folder to `tar_source()`, even when it's `R/`.
- **Packages:** every package the scripts attach with `library()` or `require()` goes into `tar_option_set(packages = c(...))`. Calls like `pkg::fn()` stay as they are.
- **Input files:** use `tar_file_read(name, "path", read = reader(!!.x))`, which creates `name_file` and `name`.
- **Output files:** use `tar_file(name, write_fn(value, "path"))`, where `write_fn` writes the file, creates its folder if needed, and returns the path.
- **Sourced helpers:** a file that only defines functions is loaded where it is, with `tar_source(c("<functions folder>", "helpers.R"))`. A helper with top-level work (reading data, setting options) is converted like any Source Script.
- **Handoff Files** (`saveRDS()` in one script, `readRDS()` in a later one) become a direct dependency between Targets. Don't write the file.
- **Leave storage formats alone.** Don't set `format =`, `tar_qs()`, `tar_parquet()` or `{crew}` during a Conversion, even though the house style suggests `format = "qs"` by default. Those are Enhancements.

## Lines to drop

These don't belong in a Pipeline. Drop each one and record it, with its file, line and reason, in the report:
- `setwd()`, `rm(list = ls())`, `install.packages()`, `View()`, `readline()`, `browser()`;
- bare console output: `print()`, `head()`, `str()`, `summary()` or a lone object name on its own line.

If a dropped line computes something a later line uses, it's a Step and stays.

## Step Map (`targetfy-map.json`)

```json
{
  "targets": {"sales_clean": "df", "model": "model", "model_summary": "coefs"},
  "handoff_files": ["tmp/df.rds"],
  "stochastic": ["rf_fit"]
}
```

- `targets` maps each Target to the script variable holding its Step. Map a Target only if that variable still holds the Step's value **when the Script Sequence ends**. If the variable is overwritten later, leave the Target out; the check reports it as `not_compared`.
- `handoff_files` lists every Handoff File, as a path relative to the project.
- `stochastic` lists the Targets you know depend on random numbers in ways the check can't see, such as a model with its own internal seed. The check finds the rest itself.
