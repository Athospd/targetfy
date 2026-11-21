# 1. An AI model performs the Conversion; a fixed R check verifies it

Date: 2026-11-21
Status: Accepted

## Context

Source Scripts are arbitrary, often messy R: `setwd()`, `rm(list = ls())`, a variable reassigned many times, side effects mixed into the analysis, poor names. targetfy must turn them into a Pipeline that is Equivalent to the original.

Options considered:

- **A fixed program that parses the code.** Same input always gives the same output, but it can't restructure messy code, group steps into sensible Targets, or name things well.
- **An AI model alone.** It handles messy code, but it can silently change behaviour, which breaks the core promise of Equivalence.
- **Both.** The AI model performs the Conversion. A fixed check written in R then verifies the Generated Files: they parse, `targets::tar_validate()` and `tar_manifest()` succeed, `tar_make()` runs, and the final objects and written files match the Source Script's.

## Decision

Use both. The AI model writes the Generated Files. A fixed R check is the authority on whether a Conversion or Enhancement is accepted.

## Consequences

- targetfy is mainly an AI skill plus an R checking script, not a parser or code transformer.
- Equivalence can only be fully verified when the Source Script can actually be run; what to do when it can't is decided separately.
- Every Enhancement must pass the same check, so Enhancements can't quietly break Equivalence.
