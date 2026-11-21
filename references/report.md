# Conversion Report (`targetfy-report.md`)

Write it for the user. Every section is required; write "None" for an empty one.

```markdown
# targetfy Conversion Report

**Status:** equivalent | not equivalent | Equivalence unverified (static check only)
**Script Sequence:** 1. `01_load.R`  2. `02_model.R`
**Checked:** 2026-11-21, 3 check runs

## Targets
| Target | Step (script variable) | Check | Notes |
|---|---|---|---|
| sales_clean | `df` | match | |
| rf_fit | `rf` | structure match | stochastic: value changes with the seed |
| sales_file | — | not compared | input file tracking |

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
```

Take the check columns from the latest `result.json`. Never upgrade a result: a `structure_match` is reported as "structure match", not "match".
