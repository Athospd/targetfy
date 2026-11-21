---
name: targetfy
description: Convert existing R scripts into an equivalent {targets} pipeline (_targets.R plus functions), verified by running both, then offer optional Enhancements (branching, storage formats, parallel workers). Use when the user wants an R script, or a sequence of R scripts, "targetified", turned into a targets pipeline or DAG, or made cacheable/reproducible with targets.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash
---

# targetfy

Turn a **Script Sequence** (one or more `.R` files, listed by the user, in run order) into a `{targets}` **Pipeline** that is **Equivalent** to it: it produces the same final objects and written files. Terms are defined in `GLOSSARY.md` in this skill's folder. The bundled R check (`scripts/check.R`) decides whether a Conversion is accepted; your own judgement about Equivalence never replaces it.

**Hard guardrail:** write only Generated Files: the Pipeline script, the functions folder, the Step Map and the Conversion Report, under the names chosen in preflight. Leave every existing file exactly as it is: Source Scripts, sourced helpers, data, `.Rprofile`, `renv.lock`. Use Edit only on Generated Files. Install nothing: if a package is missing, say so and stop.

## 1. Preflight

1. **Find R.** Use `Rscript` on the PATH. On Windows, if it isn't there, use the highest-versioned `C:/Program Files/R/R-*/bin/Rscript.exe`. Confirm that `targets`, `tarchetypes`, `callr` and `jsonlite` load. If any is missing, stop and name it.
2. **Get the Script Sequence.** Take the files and their order exactly as the user lists them. If the user hasn't listed them, ask. Never infer membership or order from file names or a `run_all.R`. The **project** folder is the user's working directory, unless they name another. Paths are relative to it.
3. **Accept only `.R` files.** Stop with a clear message for:
   - `.Rmd`, `.qmd`, `.ipynb`: planned, not yet supported.
   - `.Rnw`, files inside an R package (a `DESCRIPTION` file next to `R/`), Shiny apps: these aren't linear analyses.
4. **Choose the Generated File names.**

   | | `_targets.R` absent | `_targets.R` exists |
   |---|---|---|
   | Pipeline script | `_targets.R` | `targets_<name>.R` |
   | Store | `_targets/` | `_targets_<name>/` |
   | Step Map | `targetfy-map.json` | `targetfy-map_<name>.json` |
   | Conversion Report | `targetfy-report.md` | `targetfy-report_<name>.md` |

   - `<name>` is the Source Script's file name without `.R`: `analysis.R` gives `targets_analysis.R`. For a Script Sequence of several files, ask the user for a short name for the bundle, and suggest the project folder's name.
   - When `_targets.R` exists, tell the user: "Since `_targets.R` already exists, I'm creating `targets_<name>.R` instead." Its own store keeps the existing pipeline's cached results untouched.
   - If the chosen Step Map or Conversion Report already exists, it's an earlier targetfy run. Ask before replacing those files.
   - Functions go in `R/` if it's absent or empty, otherwise in `R_targets/`. Tell the user which one.

Done when R and its packages are confirmed, the Script Sequence is fixed, and every Generated File name is chosen.

Convert every Script Sequence that passes preflight, however small or simple. Preflight's stops are the only reasons not to convert: a three-line script still gets its Pipeline. If the Pipeline gains little, say so in the report's summary and convert anyway.

## 2. Read

Read every Source Script in full, plus every file they `source()`. Then list:
- the **Steps**;
- the input files read and the output files written;
- the **Handoff Files**;
- the lines to drop;
- the **Unresolved Objects**: names that are used but never defined, loaded or attached;
- anything that uses random numbers.

Read `references/conversion.md` now. It defines Steps and the code rules.

If there are Unresolved Objects, resolve each one with `references/unresolved-objects.md` before writing anything.

Done when every name the scripts use is accounted for, either defined in the scripts or resolved with the user.

## 3. Write the Generated Files

Following `references/conversion.md`, write:
- one functions file per Source Script (`<script name>_functions.R`);
- the Pipeline script;
- the **Step Map**.

## 4. Check

Decide the mode:
- **Equivalence** (the default): it runs the Script Sequence and the Pipeline in throwaway copies. Ask first, offering Static instead, if the scripts reach external systems (databases, APIs, credentials) or the user has said they're slow.
- **Static**: only validates the Generated Files, and the report says Equivalence is unverified.

```
Rscript <skill folder>/scripts/check.R --project <project> --scripts a.R,b.R \
        [--pipeline targets_<name>.R] [--mode static] [--allow-large] \
        --out <temp folder>/result.json
```

Read `result.json` and act on its `status`:
- **`equivalent`** or **`static_pass`**: go to step 5.
- **`not_equivalent`** or **`static_fail`**: read each failing Target's `detail` and each failing file, fix the Generated Files, and run the check again. Stop after **3 runs** in total and go to step 5 with what you have.
- **`error`**:
  - If the Script Sequence failed on an object not found, that's an Unresolved Object you missed. Go back to step 2.
  - If the Script Sequence failed on anything else, it fails on its own. Tell the user and stop.
  - If the Pipeline failed, treat it like `not_equivalent`.
- **`needs_confirmation`**: tell the user the copy size. Re-run with `--allow-large` or `--mode static`, as they choose.

## 5. Report

Write the Conversion Report following `references/report.md`, and give the user a short summary in chat: the status, the number of Targets and their results, the lines dropped, and anything left unverified.

Done when every dropped or changed line, every Unresolved Object decision and every Target's check result appears in the report.

## 6. Enhancement wizard

Only after `equivalent` or `static_pass`: offer Enhancements, one at a time, following `references/enhancements.md`. The user can decline them all, in which case the work is complete.
