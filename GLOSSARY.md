# targetfy

targetfy turns an ordinary R script into an equivalent `{targets}` pipeline, so its steps are cached, skippable and reproducible.

## Language

### Input

**Source Script**:
The arbitrary `.R` file a user hands to targetfy to be converted.
_Avoid_: input file, legacy code, original script

**Script Sequence**:
The ordered list of Source Scripts the user explicitly names as one analysis; targetfy never guesses which files belong to it. A single file is a Sequence of one.
_Avoid_: project, script set, run order

**Handoff File**:
A file that one Source Script writes only so a later Source Script in the same Sequence can read it back; in a Conversion it becomes a direct dependency between Targets.
_Avoid_: temp file, intermediate file

**Unresolved Object**:
A name the Script Sequence uses but never defines, loads or imports.
_Avoid_: missing variable, undefined symbol

### Process

**Conversion**:
The first pass, turning a Source Script into a working, basic Pipeline that is Equivalent to it.
_Avoid_: migration, refactor, targetification

**Equivalence**:
The property that a Pipeline produces the same final objects and written files as its Source Script; intermediate variables, prints and interactive views do not count.
_Avoid_: parity, same behaviour

**Step**:
A meaningful object the Source Script builds (a dataset, model, summary or file), possibly over several statements; each Step becomes one Target.
_Avoid_: line, assignment, chunk

**Equivalence Check**:
The verification that runs the Source Script and the Pipeline in a throwaway copy of the project and compares their results.
_Avoid_: test, diff

**Static Check**:
The lighter verification used when the Source Script can't be run: the Generated Files are valid, but Equivalence stays unverified.
_Avoid_: dry run, lint

**Stochastic Target**:
A Target whose value depends on random numbers, whether from R's own random number generator or hidden inside a modelling library, so the Equivalence Check only compares its structure.
_Avoid_: random target, non-deterministic step

**Conversion Report**:
The record, shown in chat and saved among the Generated Files, of every line from the Source Script that targetfy left out or changed, why, and how each Target fared in the check.
_Avoid_: log, changelog

**Step Map**:
The record, saved among the Generated Files, of which Step each Target replaces; it tells the Equivalence Check what to compare.
_Avoid_: mapping, lineage

**Enhancement**:
An optional, follow-up pass over an existing Pipeline that adds a `{targets}` feature (Branching, parallelism, storage format, external sources) without breaking Equivalence.
_Avoid_: optimization, upgrade

**Generated Files**:
The new files targetfy writes next to the Source Script (the Pipeline, its functions, the Conversion Report and the Step Map); targetfy never modifies any existing file.
_Avoid_: output, artifacts

### Output (borrowed from `{targets}`)

**Target**:
A single node of a Pipeline: one R object or tracked file, declared with `tar_target()`.
_Avoid_: step, task, node (outside graph discussions)

**Pipeline**:
The list of Targets that defines a workflow, written to `_targets.R`.
_Avoid_: workflow, DAG definition

**Dependency Graph**:
The network of edges showing which Targets depend on upstream code, data or other Targets.
_Avoid_: DAG (informally OK), lineage

**Branching**:
Splitting one Target over subsets of data or parameters, either statically (expanded up front) or dynamically (driven by upstream values).

**Target Factory**:
A function that generates a set of Targets for a common pattern, typically from `{tarchetypes}`.
_Avoid_: archetype, template
