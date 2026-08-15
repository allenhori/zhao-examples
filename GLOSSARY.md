# Glossary

Shared vocabulary used across the examples in this repo. Scoped to what these examples actually
use — for the full picture, see each tool's own docs
([`zhao-cli`](https://github.com/allenhori/zhao-cli),
[`zhao-dbt-plan`](https://github.com/allenhori/zhao-dbt-plan),
[`zhao_dbt_utils`](https://github.com/allenhori/zhao_dbt_utils)).

**Baseline** — the "before" state a change is diffed against: another compiled dbt manifest,
usually resolved from the merge-base commit with a base branch. `zhao check` computes a Baseline
automatically (via `--against`) or accepts one directly (`--state`).

**Breaking change** — a change that fires a `zhao-cli` Rule at `error` severity: something a
downstream model actively depends on (a column, in these examples) was removed or altered in a
way the downstream reference can no longer resolve.

**Rule** — a named, fixed classification `zhao-cli` applies to a detected change (e.g.
`column-removed-with-active-references`). Each Rule has a severity; only `error`-severity Rules
fail `zhao check`.

**Node** — a single model (or seed) in a dbt project's compiled dependency graph, as
`zhao-dbt-plan` and `zhao-cli` both read it from `manifest.json`.

**Microbatch model** — a dbt model materialized in time-sliced batches (via dbt's own
`materialized: incremental, incremental_strategy: microbatch` config), each batch covering an
`event_time_start`/`event_time_end` window.

**Entry Node** — the model(s) `zhao-dbt-plan` starts planning from: whichever node(s) in
`--select`'s resolved selection have no upstream parent also inside that selection.

**Anchor** — an explicit `--event-time-start`/`--event-time-end` window pinned to one specific
model (via `--anchor`) inside the selection, instead of applying to every Entry Node. Used for a
backfill: "this one model needs to reprocess this exact range," with the planner cascading the
correctly widened window to everything upstream of it.

**Cascading window** — the widened time window `zhao-dbt-plan` computes for each tier of a
microbatch chain, by walking each model's own `lookback`/`lookahead` config outward from either an
Anchor or the default Entry Node window.

**`lookback` / `lookahead`** (`meta.zhao` config) — how many days (or weeks) before/after a
model's own batch window it needs to read from an upstream, to compute a correct rolling-window
result.

**Backfill** — reprocessing a past range of batches (as opposed to the normal forward/incremental
run), typically because source data changed or a bug is being corrected. Modeled in these examples
via `zhao-dbt-plan --anchor` with an explicit past window.

**`wref()`** ("windowed ref") — a `zhao_dbt_utils` macro that's a drop-in replacement for dbt's
`ref()`: when the calling model has a `meta.zhao` block, it automatically widens the read to that
model's configured `lookback`/`lookahead`; when it doesn't, it behaves exactly like plain `ref()`.
