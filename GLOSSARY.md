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
