# Conversion Report (`targetfy-report.md` or `targetfy-report_<name>.md`)

Write it for the user. Every section is required; write "None" for an empty one.

```markdown
# targetfy Conversion Report

- **Status:** equivalent | not equivalent | Equivalence unverified (static check only) | Equivalence unverified (the scripts failed to run) | not checked (R or packages missing)
- **Script Sequence:** 1. `01_load.R`  2. `02_model.R`
- **Checked:** 2026-11-21, 3 check runs
- **R:** 4.4.1 (`C:/Program Files/R/R-4.4.1/bin/x64/Rscript.exe`, chosen by `find-r.R`; say why when it isn't the one on the PATH)

## Why it wasn't verified
Only when the status isn't "equivalent" or "not equivalent". For example: `analysis.R` failed to run at line 12: `could not find function "lgb.train"`. The comparison couldn't run, so the Pipeline was generated anyway and passed the Static Check. Or: R / the `targets` package isn't installed, so no check ran. Or: `notapkg` isn't installed, so the check returned `not_checked`; list every entry of `missing_packages`. Say what to install or fix to get it verified.

## Targets
| Target | Step (script variable) | Check | Notes |
|---|---|---|---|
| sales_clean | `df` | match | |
| rf_fit | `rf` | structure match | stochastic: value changes with the seed |
| sales_file | — | not compared | input file tracking |
| model_fit | `fit` | unverified | after the failure point: this code never ran |

## Files written by the scripts
| File | Check | Notes |
|---|---|---|
| out/coefs.csv | match | |
| out/plot.pdf | exists | PDF content embeds metadata; only existence compared |
| tmp/df.rds | handoff | replaced by a direct dependency |
| data/sales.csv | match | redirected: the Pipeline writes it as `data/sales_targetfy.csv` |

## Lines left out
| File:line | Code | Reason |
|---|---|---|
| analysis.R:1 | `rm(list = ls())` | clears the session; not needed in a Pipeline |
| report.qmd:14 | `` `{r} nrow(big)` `` | inline code: prints into the prose only |
| report.qmd:17 | chunk with `eval: false` | never runs when the document is rendered |

## Script flow
One row per `read.json` finding, and what the Pipeline does about it.
| Finding | Where | What the Pipeline does |
|---|---|---|
| `sales` changed after `model` used it (cycle) | clean.R:4 | two Targets: `sales_raw`, then `sales` |
| `data/sales.csv` read and overwritten | clean.R:1, clean.R:13 | writes `data/sales_targetfy.csv` instead (user's choice); `data/sales.csv` is no longer changed |
| loop carries `x` between iterations | clean.R:9 | kept inside `newton_sqrt2()` |
| loop over `files` has independent iterations | regional_trends.R:7 | one Target; offered as branching below |
| `helpers.R` only defines functions | analysis.R:2 | loaded in place: `tar_source(c("R", "helpers.R"))` |
| `options(contrasts = ...)` | analysis.R:4 | set in the Pipeline script, before `list()` |
| `set.seed(42)` right before the only random Step | analysis.R:5 | moved into `make_data()`: exact match |
| `try(extra <- read.csv("absent.csv"))` | analysis.R:22 | `extra` has `error = "null"`; it failed in the check, as in the script (tolerated) |

## Unresolved Objects
| Name | Found in | Decision |
|---|---|---|

## Still failing
What still fails after the last run, and what was tried each time.

## Enhancements
Filled in by the Enhancement wizard: each one offered, accepted or declined, and its check result.

## Run it
`targets::tar_make()` builds the Pipeline; `targets::tar_visnetwork()` shows the graph.
(For `targets_<name>.R`, pass the script and its store: `targets::tar_make(script = "targets_<name>.R", store = "_targets_<name>")`, and the same two arguments to `tar_visnetwork()` and `tar_read()`.)
```

For a notebook, name places as `read.json` does (`report.qmd:42`, `nb.ipynb:cell 3, line 2`), and list every path rewritten to be relative to the project.

Take the check columns from the latest `result.json`; when there is none (unchecked), every Target is "not checked". When there's a `script_failure`, mark each Target with `after_failure: true` as "unverified, after the failure point" and the others as "unverified". Never upgrade a result: a `structure_match` is reported as "structure match", not "match".
