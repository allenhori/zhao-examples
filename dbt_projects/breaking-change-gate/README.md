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
4. **Only if step 3 passed** — explicitly, via `if: steps.zhao_check.outcome == 'success'` on
   every step from here on, not GitHub Actions' implicit default: `zhao diff --format json`,
   parsed with `jq` into the changed-or-impacted model list, feeding
   `dbt build --target staging --select <that list>` — a real build into an isolated `staging`
   schema (see profiles.yml), never the schema `dev` seeds/compiles against. A step afterward
   queries that schema directly and prints exactly what landed there, confirming the impacted
   list against the real database, not just the command that was supposed to produce it.
5. For comparison only (not built): what `dbt ls --select state:modified+` would have selected
   against the same baseline.

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

and the job fails. See the pull request against this example titled as a deliberate breaking-change
demo (left open on purpose) for a live instance of exactly this.

## `zhao check` vs `zhao diff` — same engine, different exit-code contract

`zhao diff` runs the *identical* engine as `zhao check` — same Baseline resolution, same diff,
same Rule evaluation, same report — with one difference: it always exits `0`, regardless of
whether a Rule fired at `error` severity. `zhao check` is the CI gate; `zhao diff` is the
dev-time "just show me what changed" command, safe to run without ever failing your terminal
session or a script that isn't specifically trying to gate on it.

The workflow runs both, back to back, against the exact same PR (`if: always()` on the `zhao
diff` step, so it still runs — and its exit code is still visible in the log — even after `zhao
check` has already failed the job above it). Verified locally against the same breaking change
(`last_name` removed from `stg_customers`): both commands print the byte-identical report;
`zhao check` exits `1`, `zhao diff` exits `0`.

## `zhao check`'s JSON output driving a real `dbt build`, only after the gate passes, into an isolated staging schema

`zhao check` gates the PR — nothing below it runs at all if it fails, and that's not an emergent
side effect of step ordering: every step from here on carries an explicit
`if: steps.zhao_check.outcome == 'success'` condition, spelled out in the workflow file and
visible as a skipped (not run-and-ignored) step in the Actions UI when a real breaking change is
caught. Once past that gate, a second read of the same underlying diff — via `zhao diff
--format json`, which always exits zero regardless of severity — is what actually drives what
gets built next. The workflow's remaining steps parse that JSON with `jq`, build a `dbt build
--target staging --select <...>` command from it, and run it:

```bash
zhao diff --against "origin/${BASE_REF}" --format json > diff.json
jq -r '((.changes // [])[].node | split(".") | last), ((.impacted_models // [])[])' diff.json \
  | sort -u
```

`.changes[].node` is every model the diff itself touched (the file-level change); `.impacted_models`
is the separate list of models a `[BREAKING]` finding actually reached downstream. The union of
the two is exactly what needs re-verifying — nothing more.

### Why this beats `dbt build --select state:modified+`

dbt's own `state:modified+` selector has no idea what changed *inside* a model — it flags a model
as "modified" the moment its compiled SQL differs at all, then pulls in its **entire** downstream
cone regardless of whether any of those downstream models actually read the part that changed.
`zhao`'s list is column-level-lineage-aware: it only includes a downstream model when a real
finding says that model is actually affected.

Verified locally with a real, additive, non-breaking PR (a new `email_lower` column added to
`stg_customers`, nothing downstream reading it yet):

| Selector | Models selected |
|---|---|
| `dbt ls --select state:modified+` (baseline: this PR's merge-base) | `stg_customers`, `dim_customers`, `fct_orders` (3) |
| zhao's changed-or-impacted list (`zhao diff --format json`) | `stg_customers` (1) |

Same PR, same underlying dbt project — `state:modified+` rebuilds the whole downstream cone on
every change because it can't tell that `dim_customers` and `fct_orders` never touch the new
column; zhao's list stays exactly as large as what actually needs checking. On a bigger project
with deeper chains this gap only grows. The CI workflow runs both selectors side by side (the
`state:modified+` one printed for comparison, not built) so the difference is a real number in
every job log, not a claim in this README.

The actual `dbt build --target staging --select stg_customers` for that same PR lands in the
`staging` schema, isolated from `dev` — and the workflow's next step queries
`information_schema.tables` in that schema directly and prints what's actually there, separating
the one impacted model that was built from the seed data (`raw_customers`, `raw_orders`) present
only because the model needs it to build against. Real proof against the database, not a claim
about what the build command should have done.

## `zhao lineage` — a structural query, not a diff

Everything above is `zhao check`/`zhao diff`: a Baseline comparison, asking "what changed?"
`zhao lineage` asks a completely different question — "what's upstream/downstream of this model
*right now*?" — over the current project's compiled state alone. No Baseline, no git, no merge-base
resolution; it reads `target/manifest.json` and nothing else.

```bash
zhao lineage dim_customers --text
```

```
Upstream:
  model model.breaking_change_gate.stg_customers
Downstream:
  model model.breaking_change_gate.fct_orders
```

A bare target shows both directions; `+dim_customers` (prefix) shows upstream only,
`dim_customers+` (suffix) shows downstream only — dbt's own selector syntax, not zhao's own.

HTML is `zhao lineage`'s actual **default** output mode, not an opt-in flag — `--text` is what
opts out of it, the reverse of how `--html` works on `zhao-dbt-plan`. Running it plain:

```bash
zhao lineage --html lineage_report_dim_customers.html dim_customers
```

produces a self-contained, interactive HTML graph — pan, zoom, click a node to see its columns —
committed in this repo as [`lineage_report_dim_customers.html`](lineage_report_dim_customers.html),
a real file you can open directly, not a description of one. The
[`zhao-lineage` workflow](../../.github/workflows/zhao-lineage.yml) regenerates it on every PR
touching this project and fails the job if the regenerated report differs from the committed
copy (the export is fully deterministic given the same manifest — verified locally, byte-for-byte
identical across two separate runs) — so the committed artifact can never silently drift out of
sync with the project it's describing.

## Run it yourself

```bash
cd dbt_projects/breaking-change-gate
pip install dbt-core dbt-duckdb
export DBT_PROFILES_DIR=.
dbt seed
dbt compile
zhao check --against master   # from a branch with a real diff against master

# The JSON-driven build step -- only meaningful once `zhao check` above has actually
# passed; nothing here should ever run against a change zhao flagged as breaking:
zhao diff --against master --format json > diff.json
SELECT=$(jq -r '((.changes // [])[].node | split(".") | last), ((.impacted_models // [])[])' diff.json | sort -u | paste -sd ' ')
dbt seed --target staging   # prerequisite source data for the isolated staging schema
[ -n "$SELECT" ] && dbt build --target staging --select $SELECT

# Lineage (no Baseline/diff involved at all):
zhao lineage dim_customers --text
zhao lineage --html lineage_report_dim_customers.html dim_customers
```
