# targetfy <img src="man/figures/logo.png" align="right" height="139" alt="targetfy hex sticker" />

A Claude Code skill that turns existing R scripts and R notebooks (`.qmd`, `.Rmd`, `.md`, R-kernel `.ipynb`) into an equivalent [`{targets}`](https://books.ropensci.org/targets/) pipeline, then offers optional Enhancements (dynamic branching, storage formats, parallel workers, rendering the document from the pipeline).

It never changes your files. It writes `_targets.R` (or `targets_<name>.R` when `_targets.R` already exists), a functions folder, a Step Map and a Conversion Report next to your scripts. A script sitting loose in Downloads or Desktop gets its own new folder, with a copy of the script and only the files it reads. A bundled R check then runs your scripts and the new Pipeline in throwaway copies and compares their results before the Conversion is accepted.

Scripts aren't always DAGs: a variable changed after something used it, a file read and then overwritten, a loop whose iterations feed each other. Before converting, a flow scan finds these patterns, so the Pipeline gets one Target per version, writes to a new path instead of overwriting its own input, and keeps stateful loops whole. The check also fails any Pipeline that is out of date right after it's built. It then changes each input file, one at a time, and checks that the pipeline reruns exactly the targets whose results change in your scripts. An input read but not tracked (a hidden dependency) fails the check, instead of going stale later. Code that isn't a step goes into the Pipeline's setup: functions defined in the script and sourced helpers into `tar_source()`; `set.seed()`, `rm()`/`gc()` and in-house packages into `tar_option_set()`; `options()` before the targets.

[![Watch the 34-second walkthrough: a real targetfy run, from the R script to the Pipeline, its DAG and the report](demo/walkthrough/thumbnail.png)](https://www.youtube.com/watch?v=f4F8yNo_d8Y)

## Install

```sh
git clone https://github.com/Athospd/targetfy.git ~/.claude/skills/targetfy
```

Then, in Claude Code: `/targetfy`, or ask it to convert your R script(s) to targets.

Requires R >= 4.1 with `targets` (>= 1.12), `tarchetypes`, `callr` and `jsonlite`. targetfy never installs packages.

## Layout

| Path | What it is |
|---|---|
| `SKILL.md`, `references/` | the skill |
| `scripts/check.R` | the check that accepts or rejects a Conversion |
| `scripts/find-r.R` | picks the R installation where targetfy's and the scripts' packages all load |
| `scripts/read.R` | the flow scan, and the R code extracted from notebooks; runs nothing |
| `vendor/targets-r-skill/` | pinned copy of [targets-r-skill](https://github.com/statzhero/targets-r-skill) by Ulrich Atz, used as the house style |
| `GLOSSARY.md`, `docs/` | vocabulary, design and decisions |
| `tests/` | the check's tests: `Rscript -e 'testthat::test_dir("tests/testthat")'` |
