# breaking-change-gate

A small DuckDB dbt project that demonstrates [`zhao-cli`](https://github.com/allenhori/zhao-cli)
as a CI breaking-change gate: `zhao check` diffs a pull request's compiled dbt project against
its base branch and fails the build if the diff removes or narrows something a downstream model
actually depends on.

## The project

Three layers, seeded from two CSV files so the whole thing runs with no warehouse credentials:

```
raw_customers, raw_orders   (seeds)
        │
        ▼
stg_customers, stg_orders   (staging: renamed/cleaned columns)
        │
        ▼
dim_customers                (mart: adds a computed full_name)
        │
        ▼
fct_orders                   (mart: joins orders to the customer's display name)
```

- `stg_customers` renames the raw seed's columns and passes `last_name` through unchanged.
- `dim_customers` reads `stg_customers` and computes `full_name` from `first_name || ' ' || last_name`.
- `fct_orders` reads both `stg_orders` and `dim_customers`.

## What's tested

The [`breaking-change-gate` workflow](../../.github/workflows/breaking-change-gate.yml) runs on
every pull request that touches this folder:

1. Install dbt-core + dbt-duckdb and `zhao-cli`.
2. `dbt seed && dbt compile` — produces this PR's compiled `manifest.json`.
3. `zhao check --against origin/<base-branch>` — zhao resolves the merge-base with the base
   branch, compiles *that* commit as the Baseline in a temporary git worktree, and diffs it
   against the PR's current compiled state.

`zhao check` exits non-zero (failing the job) only when a change reaches a Rule at `error`
severity — for example, a column an active downstream reference depends on being removed. It
exits zero for additive or non-breaking changes, so this gate isn't "anything changed" — it's
"something changed that would actually break a consumer."

## How to read the CI output

A clean PR's `zhao check` step prints `No changes detected.` (or, for a non-breaking change, a
`Changed:` section with no `[BREAKING]` lines) and exits `0`.

A PR that removes a column something downstream reads produces output like:

```
Changed:
  model model.breaking_change_gate.stg_customers:
    - column removed: last_name
  model model.breaking_change_gate.dim_customers:
    - column removed: last_name

Downstream impact:
  model model.breaking_change_gate.dim_customers:
    [BREAKING] last_name removed from model model.breaking_change_gate.stg_customers breaks reference via last_name (column-removed-with-active-references)
    [BREAKING] last_name removed from model model.breaking_change_gate.stg_customers breaks reference via full_name (column-removed-with-active-references)

Summary: 2 model(s) changed, 2 column(s) changed, 2 breaking, 0 warning

Impacted models: dim_customers
```

and the job fails. See the open pull request against this example titled as a deliberate
breaking-change demo for a live instance of exactly this — that PR is left open on purpose so
its failing CI run stays visible.

## Run it yourself

```bash
cd dbt_projects/breaking-change-gate
pip install dbt-core dbt-duckdb
export DBT_PROFILES_DIR=.
dbt seed
dbt compile
zhao check --against master   # from a branch with a real diff against master
```
