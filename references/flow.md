# Script flow: versions, in-place files and loops

A script is a sequence, not a graph. The same name can hold several values over time, a file can be read and then overwritten, and a loop can feed each iteration into the next. A Pipeline is a graph, in which each Target is built once from the Targets it depends on. Mapping one variable to one Target, the naive way, turns these patterns into cycles (`graph contains a cycle`), or into a Pipeline that's never up to date.

`scripts/read.R` finds them without running anything. Run it in section 2, before writing:

```
<chosen Rscript> <skill folder>/scripts/read.R --project <project> --scripts a.R,report.qmd \
        --tangle-dir <temp folder>/tangled --out <temp folder>/read.json
```

Handle each entry of `findings` as follows, and record each one in the report's **Script flow** section.

## `reassigned`: a variable changed after another Step used it

```r
sales <- read.csv("data/sales.csv")
model <- lm(revenue ~ units, data = sales)      # uses sales (version 1)
sales$predicted <- predict(model, sales)        # sales version 2 reads model
```

A single `sales` Target would depend on `model`, which depends on `sales`: a cycle (`cycle: true`). Even without a cycle (`cycle: false`), `model` needs the first value and the end of the script holds the second.

- Give each version its own Target, named after what it holds: `sales_raw` → `model` → `sales`. The last version keeps the script's name.
- In the Step Map, map only the last version to the variable (`"sales": "sales"`). Earlier versions are not compared, because the check sees only the script's final values.
- Statements that keep changing the same variable with nothing reading it in between remain one Step, as before.

## `in_place_file`: a file read and then overwritten

```r
sales <- read.csv("data/sales.csv")
...
write.csv(sales, "data/sales.csv")
```

A Pipeline that tracks `data/sales.csv` as input and also writes it is out of date as soon as it's built. Every `tar_make()` would then transform its own output again. Ask the user, recommending the first option:

- **a. Write to a new path** (recommended): the file Target writes `data/sales_targetfy.csv`, and the user's input stays as it is. Add `"redirected_files": {"data/sales.csv": "data/sales_targetfy.csv"}` to the Step Map, so the check compares the script's file with the Pipeline's new path. The report says that the Pipeline no longer changes `data/sales.csv`.
- **b. Keep writing in place**: only if the user insists. Read the input with a plain `tar_target(sales_raw, read.csv("data/sales.csv"))`, without file tracking, so the Pipeline doesn't re-run on its own output. Warn them that a fresh `tar_make()` (for example after `tar_destroy()`) transforms the already-transformed file. The check reports this choice as `outdated_after_build` only if the input is tracked.

## `handoff`: a file written and then read back

This is a Handoff File, within one script or across scripts. Convert it to a direct dependency and list it in `handoff_files`, unless the user also keeps the file as a result (then it's both an output file Target and a dependency).

## `carried_loop`: iterations that feed each other

`while` and `repeat` loops, `Reduce()`/`accumulate()`, and `for` loops whose variables read their own previous value (`x <- x / 2 + 1 / x`, `total <- total + ...`) carry state from one iteration to the next.

- Keep the whole loop inside one Target's function, together with its starting value.
- Never split iterations into Targets or branches: iteration *k* needs iteration *k − 1*.

## `branch_candidate`: independent iterations

A `for` loop that only fills a collection at the loop variable's position (`fits[[region]] <- ...`), or appends to it, or an `lapply()`/`map()` call. Convert it as one Target first, with the loop inside the function. It's then a candidate for the dynamic-branching Enhancement (`references/enhancements.md`). Don't branch during the Conversion.

## `global_state`: changes outside the variables

| Flag | What to do |
|---|---|
| `by_reference` (`:=`, `set*()`) | start the function with `x <- data.table::copy(x)`: otherwise it changes the upstream Target's value in memory |
| `global_assign` (`<<-`) | return the value from the function and make it a Target |
| `assign` | name the variable explicitly, so it can become a Target |
| `attach` | pass the data as an argument |

Options, environment variables, seeds, memory and error handling are `pipeline_setup` findings: see `references/setup.md`.

## `defined_later`: used before it's defined

A name read at one point but first assigned later, usually in a later script. Flag it as an ordering problem (`references/unresolved-objects.md`). Never reorder the Script Sequence yourself.

## When the check still finds a cycle

If the check fails with "the Pipeline's graph has a cycle", a Target depends on itself through other Targets. Look for a Target whose function reads a name that one of its downstream Targets also builds, and split the versions as described under `reassigned`. If it reports `outdated_after_build`, the Pipeline changes its own inputs: see `in_place_file`.
