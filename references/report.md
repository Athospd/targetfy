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

## Lines left out
| File:line | Code | Reason |
|---|---|---|
| analysis.R:1 | `rm(list = ls())` | clears the session; not needed in a Pipeline |

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

Take the check columns from the latest `result.json`; when there is none (unchecked), every Target is "not checked". When there's a `script_failure`, mark each Target with `after_failure: true` as "unverified, after the failure point" and the others as "unverified". Never upgrade a result: a `structure_match` is reported as "structure match", not "match".
