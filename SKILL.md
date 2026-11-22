---
name: targetfy
description: Convert existing R scripts and R notebooks (.qmd, .Rmd, .md, R-kernel .ipynb) into an equivalent {targets} pipeline (_targets.R plus functions), verified by running both, then offer optional Enhancements (branching, storage formats, parallel workers, rendering the document). Use when the user wants an R script, notebook, or a sequence of them "targetified", turned into a targets pipeline or DAG, or made cacheable/reproducible with targets.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash
---

# targetfy

Turn a **Script Sequence** (one or more `.R` files or R notebooks, listed by the user, in run order) into a `{targets}` **Pipeline** that is **Equivalent** to it: it produces the same final objects and written files. Terms are defined in `GLOSSARY.md` in this skill's folder. The bundled R check (`scripts/check.R`) decides whether a Conversion is accepted; your own judgement about Equivalence never replaces it.

**Hard guardrail:** write only Generated Files: the Pipeline script, the functions folder, the Step Map and the Conversion Report, under the names chosen in preflight, plus the Working Folder for a Loose Script (step 1.2). Leave every existing file exactly as it is: Source Scripts, sourced helpers, data, `.Rprofile`, `renv.lock`. Use Edit only on Generated Files. Install nothing: when a package is missing, name it for the user and carry on.

**Keep going.** Once preflight has fixed the Script Sequence and the names, targetfy always writes the Generated Files and the report. Anything that blocks verification (R or a package missing, scripts that fail to run) lowers how much gets checked, and the report and chat say exactly what was skipped and why. It never stops the Conversion.

## 1. Preflight

1. **Get the Script Sequence.** Take the files and their order exactly as the user lists them. If the user hasn't listed them, ask. Never infer membership or order from file names or a `run_all.R`. The **project** folder is the user's working directory when the Source Scripts are inside it; otherwise it's the folder holding them. The user can name another. Paths are relative to it.
2. **Loose Script?** A Source Script is loose when the project folder isn't a project: it has none of `*.Rproj`, `.git/`, `renv.lock`, `.here`, `DESCRIPTION`, `_targets.R` or `R/`, and it's a catch-all folder (Downloads, Desktop, Documents, the home folder, a temp folder) or most of its files have nothing to do with the scripts. Then, without asking:
   - create a **Working Folder** next to the scripts, named after the first Source Script (`07-dois-modelos.R` gives `07-dois-modelos/`; if that name is taken, `07-dois-modelos_targetfy/`), and copy the Source Scripts into it. It becomes the project folder.
   - In section 2 (Read), once you know which files the scripts read, copy those too, at the same relative paths. A file that doesn't exist stays missing, and the check will report it.
   - Tell the user in one line, calmly: "`07-dois-modelos.R` is a loose file in Downloads, so I'm working in a new folder, `Downloads/07-dois-modelos/`, with a copy of it. Your original file isn't touched, and nothing else in Downloads is read or run."
   - Never mention the size or number of the folder's other files: they're out of scope, and naming them makes it sound as if they'll be loaded.
3. **Accept `.R` files and notebooks:** `.qmd`, `.Rmd`, `.md` and `.ipynb` with an R kernel. A notebook's R code chunks or cells, in order, are its Source Script (`references/notebooks.md`). Stop with a clear message for:
   - an `.ipynb` with a Python (or other non-R) kernel: only R notebooks are supported;
   - `.Rnw`, files inside an R package (a `DESCRIPTION` file next to `R/`), Shiny apps: these aren't linear analyses.
4. **Choose the R installation.** People often have several R versions installed, with packages spread across them, and the `Rscript` on the PATH isn't always the one they use. Start any `Rscript`: the one on the PATH, or on Windows any `C:/Program Files/R/R-*/bin/Rscript.exe`. Then run:

   ```
   Rscript <skill folder>/scripts/find-r.R --project <project> --scripts a.R,b.R --out <temp folder>/r.json
   ```

   It finds every R installation and, in a fresh session of each, loads targetfy's packages (`targets`, `tarchetypes`, `callr`, `jsonlite`) and every package the scripts need: `library()`, `require()`, `pkg::fn`, `set_engine("<pkg>")`. It reads the scripts without running them. Loading the packages, rather than only checking that they're installed, catches version conflicts such as `namespace 'yardstick' 1.3.1 is being loaded, but >= 1.4.0 is required`. In `r.json`:
   - `chosen` is the `Rscript` to use for every later step: the check, the graph and anything else you run. It's the installation where everything loads, preferring the one on the PATH, then the highest version.
   - If `chosen` isn't on the PATH (`chosen_is_path: false`), tell the user in one line: "I'm using R 4.5.1, since it's the one where all the packages your script needs load; the `Rscript` on your PATH (R 4.4.1) is missing `vip`."
   - When `status` is `missing_packages`, no installation loads everything. `chosen` has the fewest problems. Show the user, for each installation, what's missing or fails to load, so they can choose where to install. Carry on with `chosen`. Its missing packages limit the check, which then falls back to the Static Check.
   - When `status` is `no_r`, or `chosen` can't load targetfy's own packages, name what's missing and continue **unchecked**: sections 4 and 6 and the graph are skipped, and the report's status is "not checked".
   - If no `Rscript` starts at all, the same applies: continue unchecked.
5. **Choose the Generated File names.**

   | | `_targets.R` absent | `_targets.R` exists |
   |---|---|---|
   | Pipeline script | `_targets.R` | `targets_<name>.R` |
   | Store | `_targets/` | `_targets_<name>/` |
   | Step Map | `targetfy-map.json` | `targetfy-map_<name>.json` |
   | Conversion Report | `targetfy-report.md` | `targetfy-report_<name>.md` |

   - `<name>` is the file name, without its extension, of the first Source Script in the Script Sequence: `analysis.R` gives `targets_analysis.R`, a Sequence starting with `01_load.R` gives `targets_01_load.R`, and `report.qmd` gives `targets_report.R`.
   - When `_targets.R` exists, tell the user: "Since `_targets.R` already exists, I'm creating `targets_<name>.R` instead." Its own store keeps the existing pipeline's cached results untouched.
   - If the chosen Step Map or Conversion Report already exists, it's an earlier targetfy run. Ask before replacing those files.
   - Functions go in `R/` if it's absent or empty, otherwise in `R_targets/`. Tell the user which one.

Done when the R installation is chosen (or you know none can run the check), the Script Sequence is fixed, and every Generated File name is chosen.

Convert every Script Sequence that passes preflight, however small or simple. The only stops are an unsupported file type (step 3) and the user declining a question. A three-line script still gets its Pipeline. If the Pipeline gains little, say so in the report's summary and convert anyway.

## 2. Read

First run the flow scan. It runs none of the user's code:

```
<chosen Rscript> <skill folder>/scripts/read.R --project <project> --scripts a.R,report.qmd \
        --tangle-dir <temp folder>/tangled --out <temp folder>/read.json
```

- For each notebook, `read.json` gives the path of its extracted code (`tangled`), with every chunk headed by the notebook line it starts at. It also lists the chunks skipped, the inline code and any warnings. Read that file in place of the notebook, then read `references/notebooks.md`.
- `findings` lists what a naive one-variable-one-Target Conversion would get wrong: variables changed after another Step used them (`reassigned`, with `cycle: true` when one Target would depend on itself), files read and then overwritten (`in_place_file`), Handoff Files, loops that carry state, loops that could be branched, global side effects, and names used before they're defined. Read `references/flow.md` when there are any findings: it says how to handle each kind. Ask the user only about `in_place_file`.

Read every Source Script in full, plus every file they `source()`. Then list:
- the **Steps**;
- the input files read and the output files written;
- the **Handoff Files**;
- the lines to drop;
- the **Unresolved Objects**: names that are used but never defined, loaded or attached;
- anything that uses random numbers.

Read `references/conversion.md` now. It defines Steps and the code rules.

If there are Unresolved Objects, resolve each one with `references/unresolved-objects.md` before writing anything.

For a Loose Script, copy the input files into the Working Folder now (step 1.2).

Done when every name the scripts use is accounted for: defined in the scripts, resolved with the user, or assumed to exist and flagged.

## 3. Write the Generated Files

Following `references/conversion.md`, write:
- one functions file per Source Script (`<script name>_functions.R`);
- the Pipeline script;
- the **Step Map**.

## 4. Check

Ask the user which check to run, unless they've already said. The matching test runs their code, so it's their call. Explain what each one does in plain words:
- **Run and compare** (the Equivalence Check): runs the scripts and the Pipeline in a throwaway copy of the project folder, compares their results, then deletes the copy. Nothing in the user's own folder is run or changed. Mark it recommended, unless the scripts reach external systems (databases, APIs, credentials, sending email) or the user has said they're slow: then recommend the other option and say why.
- **Only validate the files** (the Static Check): checks that the Generated Files parse and form a valid Pipeline, and runs none of the user's code. The report says Equivalence is unverified.

Mention what you already know will limit the run, such as a package the scripts attach that isn't installed. Never mention the size of files the scripts don't use.

```
<chosen Rscript> <skill folder>/scripts/check.R --project <project> --scripts a.R,b.R \
        [--pipeline targets_<name>.R] [--mode static] [--allow-large] \
        --out <temp folder>/result.json
```

Read `result.json` and act on its `status`:
- **`equivalent`** or **`static_pass`**: go to step 5. If `result.json` has a `script_failure`, the Source Scripts failed to run on their own, at the `script` and `line` it names, so the check fell back to the Static Check. Equivalence is unverified, and the Targets with `after_failure: true` come from code that never ran. Before step 5, apply `references/unresolved-objects.md` if the message is an object or function not found.
- **`not_equivalent`** or **`static_fail`**: read each failing Target's `detail`, each failing file and `errors`, fix the Generated Files, and run the check again. Stop after **3 runs** in total and go to step 5 with what you have.
  - An error saying the graph has a cycle means a Target depends on itself: split the versions of a reassigned variable (`references/flow.md`).
  - A non-empty `outdated_after_build` means the Pipeline is out of date right after being built: it changes its own inputs, usually by overwriting a file it reads.
- **`not_checked`**: a package the code needs isn't installed (`missing_packages`), so the Static Check couldn't run. This is not a fault in the Conversion: don't change the Generated Files for it. Name the packages for the user and go to step 5.
- **`error`**: the Pipeline failed to build, or a Source Script wasn't found. Treat a build failure like `not_equivalent`.
- **`needs_confirmation`**: tell the user the copy size. Re-run with `--allow-large` or `--mode static`, as they choose.

## 5. Report

Write the Conversion Report following `references/report.md`, and give the user a short summary in chat: the status, the number of Targets and their results, the lines dropped, and anything left unverified.

Then show the Pipeline's graph, whatever the check's status:

```
<chosen Rscript> <skill folder>/scripts/glimpse.R --project <project> --pipeline <Pipeline script>
```

It saves `targets::tar_glimpse()` as an HTML page in the system temp folder, opens it in the browser and prints its path. Give the user that path. If it can't draw the graph (for example `visNetwork`, or a package the Pipeline attaches, isn't installed), mention it in one line and carry on.

Done when every dropped or changed line, every Unresolved Object decision and every Target's check result appears in the report, and the graph has been shown.

## 6. Enhancement wizard

Only after `equivalent` or `static_pass`, and never when unchecked or `not_checked`: offer Enhancements, one at a time, following `references/enhancements.md`. The user can decline them all, in which case the work is complete. If any Enhancement was kept, run `glimpse.R` once more at the end so the user sees the final graph.
