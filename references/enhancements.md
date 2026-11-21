# Enhancement wizard

An **Enhancement** is an optional change to a Pipeline that already passes the check. Offer them **one at a time**. Each suggestion is tied to specific Targets and says why, for example: "`fit_by_region` loops over 12 regions. Switch it to dynamic branching so each region caches separately?"

## The loop, for each accepted Enhancement

1. Save a copy of every Generated File you're about to change.
2. Apply the Enhancement, following the house style in `vendor/targets-r-skill/`.
3. Run the check with the same mode as the Conversion.
4. If the status differs from the Conversion's (for example, it was `equivalent` and is now `not_equivalent`), restore the saved copies and tell the user why the Enhancement was undone.
5. Record it in the report's Enhancements section: what was offered, the user's answer, and the check result.

Offer only the Enhancements whose condition holds, in this order:

| Enhancement | Offer it when | How | House-style reference |
|---|---|---|---|
| Storage format | a Target holds a large R object, or a large data frame | `tar_qs()` (needs `qs2`), `tar_parquet()` (needs `arrow`), `tar_nanoparquet()` | `vendor/targets-r-skill/references/targets.md` |
| Dynamic branching | a Step loops over groups, files or parameters (`for`, `lapply`, `purrr::map`, `split`) | `pattern = map(...)`, with an upstream Target holding the values to iterate over | `vendor/targets-r-skill/references/branching.md` |
| Parallel workers | branching or independent Targets mean several can run at once | `tar_option_set(controller = crew::crew_controller_local(workers = n))` | `vendor/targets-r-skill/references/performance.md` |

If an Enhancement needs a package that isn't installed, offer it only together with the instruction to install that package: the user installs it, never targetfy.

After branching, update the Step Map: a branched Target still maps to the variable holding the combined result.
