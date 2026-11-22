# targetfy Conversion Report

- **Status:** equivalent
- **Script Sequence:** 1. `analysis.R`
- **Checked:** 2026-11-22, 1 check run
- **R:** 4.4.1 (`C:/Program Files/R/R-4.4.1/bin/x64/Rscript.exe`, the one on the PATH)

## Targets
| Target | Step (script variable) | Check | Notes |
|---|---|---|---|
| sales_raw_file | — | not compared | tracks `data/sales.csv` |
| sales_raw | — | not compared | the raw read; the script overwrites `sales` |
| sales | `sales` | match | filtered to 2021+, revenue in thousands |
| by_region | `by_region` | match | |
| model | `model` | match | |
| coefs | `coefs` | match | |
| revenue_plot | `plot` | match | |
| revenue_png | — | not compared | writes `out/revenue.png` |
| coefs_csv | — | not compared | writes `out/coefs.csv` |

## Files written by the scripts
| File | Check | Notes |
|---|---|---|
| out/coefs.csv | match | |
| out/revenue.png | match | byte-identical |

## Lines left out
| File:line | Code | Reason |
|---|---|---|
| analysis.R:6 | `setwd("~/projects/sales")` | ties the script to one machine; targets runs from the project folder |
| analysis.R:7 | `dir.create("out", showWarnings = FALSE)` | the file Targets create their own folder |
| analysis.R:15 | `head(sales)` | console output only |

## Unresolved Objects
None.

## Still failing
None.

## Enhancements
None offered: the data is small and there are no loops to branch over.

## Run it
`targets::tar_make()` builds the Pipeline; `targets::tar_visnetwork()` shows the graph.
