# Notebooks as Source Scripts

A `.qmd`, `.Rmd`, `.md` or `.ipynb` (R kernel) notebook is a Source Script like an `.R` file. Its R code, in document order, is the analysis, and the prose is dropped. A Script Sequence can mix notebooks and `.R` files.

## What counts as code

`scripts/read.R --tangle-dir` writes each notebook's code as an `.R` file. Read that file (each chunk is headed by the notebook line it starts at), not the notebook. The rules it applies:

| Format | Code | Not code |
|---|---|---|
| `.qmd`, `.Rmd` | ```` ```{r} ```` chunks | ```` ```r ```` (display only), `eval = FALSE` / `#\| eval: false` chunks, other languages (`{python}`, `{sql}`, `{bash}`) |
| `.md` | ```` ```r ```` and ```` ```{r} ```` blocks | other languages |
| `.ipynb` | code cells, when the kernel is R | markdown cells; `%` and `!` lines |

- A notebook with a Python (or other non-R) kernel isn't supported: say so and stop, as for any unsupported file type.
- **YAML `params:`** become `params <- list(...)` at the top of the code, as knitting does. Convert them to one `params` Target, mapped to `params`, so a later change to the values reruns what depends on them.
- **Inline code** (`` `r nrow(big)` ``, `` `{r} nrow(big)` ``) only prints into the prose. Drop it and list it under "Lines left out", unless it assigns something.
- **Skipped chunks** (`eval = FALSE`, other languages) never ran when the document was rendered. Leave them out and list them under "Lines left out", with their line and reason. A `{sql}` chunk with `output.var` creates an R object: treat that name as an Unresolved Object.
- **`read.json` warnings**: a chunk with `error = TRUE` (knitting continues past its errors; the check doesn't), `eval` set by an expression, or `<<label>>` chunk reuse. Mention each one in the report.
- Drop `knitr::opts_chunk$set()` and `knitr::opts_knit$set()`, which only configure knitting.

## Where the code runs

knitr and Quarto run a notebook's code from the notebook's own folder, while targets runs from the project folder. The check runs a notebook from its folder, just as rendering does: from the project folder only when a `_quarto.yml` sets `execute-dir: project`. So, in the functions and the Pipeline script, rewrite relative paths so they're relative to the project. `analysis/report.qmd` reading `"../data/sales.csv"` becomes `"data/sales.csv"`. Record each rewritten path in the report.

## Names

- `<name>` for the Generated Files is the notebook's file name without its extension: `report.qmd` gives `targets_report.R` and `R/report_functions.R`.
- In the report, give notebook places as `report.qmd:42`, or `nb.ipynb:cell 3, line 2`, as `read.json` and the check's `script_failure.where` do.

## The rendered document

The Conversion only covers the computations. If the user renders the notebook, offer the **Render the document** Enhancement (`references/enhancements.md`), which makes the document a Target that reads the Pipeline's results.
