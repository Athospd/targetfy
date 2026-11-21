# 2. Bundle a pinned copy of targets-r-skill as the house style

Date: 2026-11-21
Status: Accepted

## Context

[statzhero/targets-r-skill](https://github.com/statzhero/targets-r-skill) is a Claude Code / Codex skill for *authoring* `{targets}` pipelines. It covers conventions such as functions in `R/`, `tar_file_read()` for inputs, tarchetypes factories over a manual `format =`, and no globals in commands, along with branching, debugging, performance and literate-programming references. It does not cover converting existing scripts, which is targetfy's job.

targetfy's R check enforces some of these conventions (as warnings), so the rules the AI model follows and the rules the check enforces must come from the same version.

Options considered:

- **Require users to install it separately.** It stays current automatically, but the user may have a different version than the check expects, and targetfy breaks if it is missing.
- **Only link to it.** It costs nothing, but the conventions are not actually loaded when a Conversion runs.
- **Bundle a pinned copy.** The conventions and the check always match, at the cost of updating the copy deliberately.

## Decision

Bundle a pinned copy of targets-r-skill inside targetfy, with its source commit recorded and full attribution to its author, Ulrich Atz. Its conventions are targetfy's house style for Generated Files. Update the copy deliberately and re-run the check's own tests when doing so.

## Consequences

- **License mismatch.** The repo's `LICENSE` file is MIT, but `SKILL.md`'s frontmatter declares CC-BY-4.0. Both permit reuse with attribution. targetfy keeps the MIT `LICENSE` text and credits the author per CC-BY-4.0 as well, and we should ask upstream which license applies.
- Upstream improvements reach targetfy only when someone updates the bundled copy.
- Conventions that can't always be met (for example a file path built at runtime) are check warnings, never failures.
