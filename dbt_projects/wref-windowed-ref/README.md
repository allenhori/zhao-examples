# wref-windowed-ref

A DuckDB dbt project that proves, with real compiled SQL, why plain `ref()` silently
under-computes a rolling-window microbatch model — and why
[`wref()`](https://github.com/allenhori/zhao_dbt_utils) doesn't.

## The setup

```
mb_orders_daily                       (daily microbatch of raw orders)
        │
        ├──▶ rolling_7d_revenue_plain_ref   (meta.zhao.lookback: 6, reads with ref())
        │
        └──▶ rolling_7d_revenue_wref        (meta.zhao.lookback: 6, reads with wref())
```

Both downstream models are identical in every way that matters — same materialization, same
`meta.zhao.lookback: 6` config, same intent (a 7-day trailing revenue sum) — except for one line:

```sql
-- rolling_7d_revenue_plain_ref.sql
from {{ ref('mb_orders_daily') }}

-- rolling_7d_revenue_wref.sql
from {{ wref('mb_orders_daily') }} mb_orders_daily
```

`wref()` here is installed the standalone way — [`macros/zhao_ref_standalone.sql`](macros/zhao_ref_standalone.sql)
is a direct copy of [`zhao_dbt_utils`](https://github.com/allenhori/zhao_dbt_utils)'s
`standalone/zhao_ref_standalone.sql`, dropped into this project's own `macros/` folder. No
`packages.yml`, no `dbt deps` — see that project's README for the alternative package-install
path.

## The problem, proven

dbt's own microbatch `ref()` filtering can't be overridden by a project macro — it's resolved
outside normal macro dispatch, before Jinja even renders, to build the dependency graph
statically. So a plain `{{ ref('mb_orders_daily') }}` always gets dbt's own narrow, single-batch
window, no matter what `meta.zhao` says. `wref()` works around this: it opts out of dbt's
automatic filtering (`ref(...).render()`) and applies its own `WHERE` clause instead, built from
`meta.zhao`.

Building a single day's batch (`2026-01-10`) for both models and inspecting the real compiled SQL:

**`rolling_7d_revenue_plain_ref`** — only this model's own single-day batch window:

```sql
from (select * from "wref_windowed_ref"."main"."mb_orders_daily"
      where order_date >= '2026-01-10 00:00:00+00:00'
        and order_date < '2026-01-11 00:00:00+00:00')
```

**`rolling_7d_revenue_wref`** — the same read, widened by `meta.zhao.lookback: 6`:

```sql
from (
  select * from "wref_windowed_ref"."main"."mb_orders_daily"
  where order_date >= (cast('2026-01-10 00:00:00+00:00' as timestamp) + cast(-6 as bigint) * interval 1 day)
    and order_date <  (cast('2026-01-11 00:00:00+00:00' as timestamp) + cast(0 as bigint) * interval 1 day)
)
 mb_orders_daily
```

The practical effect, run against this project's seed data: the plain-`ref()` model computes
`revenue_7d = 18.0` for `2026-01-10` (one order, from that single day). The `wref()` model
computes `revenue_7d = 75.5` — the correct sum of every order from `2026-01-04` through
`2026-01-10`. Same config, same intent, silently different (and wrong) answer without `wref()`.

## Two more ways to get the same correct window

The two models above use the **standalone** install (a copied macro file, bare `wref()` calls).
This project also has two more models proving the other undemonstrated surfaces of
[`zhao_dbt_utils`](https://github.com/allenhori/zhao_dbt_utils), both verified to produce the
exact same widened result as `rolling_7d_revenue_wref` above:

**`rolling_7d_revenue_wref_pkg`** — the **package install** path instead of standalone:
[`packages.yml`](packages.yml) pulls `zhao_dbt_utils` as a real git-based dbt package (`dbt deps`),
and the call is namespaced — `{{ zhao_utils.wref('mb_orders_daily') }}` — instead of the bare
`wref()` the standalone file gives you. Pick standalone when you want zero dependency management
(the whole macro lives in your own project, nothing to `dbt deps`); pick the package install when
you want `dbt deps`-driven upgrades to a pinned version (`revision: v0.2.0` here) without manually
re-copying a file.

**`rolling_7d_revenue_boundary_helpers`** — a third approach: instead of `wref()`'s full
`ref()` replacement, hand-write the `WHERE` clause yourself (`ref(...).render()`, dbt's own
documented pattern for rolling-window microbatch models) using `zhao_window_start()`/
`zhao_window_end()` for the two boundary expressions instead of hardcoding the day-count:

```sql
from {{ ref('mb_orders_daily').render() }}
where order_date >= {{ zhao_utils.zhao_window_start('mb_orders_daily') }}
  and order_date <  {{ zhao_utils.zhao_window_end('mb_orders_daily') }}
```

Use these when you need a custom `WHERE` clause alongside the window (an extra predicate, a join
condition) that `wref()`'s fixed shape doesn't give you room for — same `meta.zhao.lookback: 6`,
same correct window, just returning two boundary expressions instead of a full filtered subquery.

Verified locally: both new models' compiled SQL for the `2026-01-10` batch produce the identical
widened `WHERE order_date >= (... -6 days) and order_date < (...)` clause as
`rolling_7d_revenue_wref`, and all three models' output rows are byte-identical.

## Why `dbt build`, not `dbt compile`, in CI

`meta.zhao`-based widening only renders once dbt has a real per-batch context (`model.batch`),
which is only populated during an actual batch execution — plain `dbt compile` runs with no batch
selected at all, so `wref()` and plain `ref()` would compile identically (both fall back to
unwidened). This example's [CI workflow](../../.github/workflows/wref-windowed-ref.yml) instead
runs `dbt build --event-time-start "2026-01-10" --event-time-end "2026-01-11"` — a real single-day
microbatch build against DuckDB — and inspects the compiled SQL that build produces under
`target/compiled/`, which is the genuine artifact `dbt compile` would have produced for that same
batch had one been selected.

## CI

The workflow installs dbt-core + dbt-duckdb, runs `dbt deps` (installs `zhao_dbt_utils` as a real
package, for the two models that need it), seeds the raw orders, runs the single-day build above,
prints all four models' compiled SQL to the job log, diffs the plain-`ref()` vs. standalone-`wref()`
pair, and uploads all four files as a workflow artifact.

## Run it yourself

```bash
cd dbt_projects/wref-windowed-ref
pip install dbt-core dbt-duckdb
dbt deps   # installs zhao_dbt_utils, for the two package/boundary-helper models
export DBT_PROFILES_DIR=.
dbt seed
dbt build --event-time-start "2026-01-10" --event-time-end "2026-01-11"
cat target/compiled/wref_windowed_ref/models/rolling_7d_revenue_plain_ref/*.sql
cat target/compiled/wref_windowed_ref/models/rolling_7d_revenue_wref/*.sql
cat target/compiled/wref_windowed_ref/models/rolling_7d_revenue_wref_pkg/*.sql
cat target/compiled/wref_windowed_ref/models/rolling_7d_revenue_boundary_helpers/*.sql
```
