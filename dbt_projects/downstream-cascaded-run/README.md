# downstream-cascaded-run

Demonstrates [`zhao-dbt-plan`](https://github.com/allenhori/zhao-dbt-plan)'s **default** forward
cascade — no `--anchor` — using the exact same 3-tier microbatch chain as the
[`cascading-window-backfill`](../cascading-window-backfill/README.md) example. This folder has no
dbt project of its own; it documents a second invocation of that same project, so the two
scenarios can be read and CI-verified side by side.

## The contrast with `cascading-window-backfill`

Both examples plan the same chain:

```
mb_events_daily  ->  mb_device_activity_3d  ->  mb_device_activity_7d_smoothed
```

| | `cascading-window-backfill` | `downstream-cascaded-run` (this example) |
|---|---|---|
| Flag | `--anchor mb_device_activity_7d_smoothed` | *(none)* |
| Explicit window applies to | one specific model, anywhere in the chain | the Entry Node (`mb_events_daily`) |
| Scenario | "This one downstream model needs backfilling for a specific past range — what does everything upstream of it need to cover?" | "The Entry Node is running for this window — what window does each downstream tier need to cover to stay consistent?" |

Same planner, same underlying cascading-window math (each tier's own `meta.zhao`
`lookback`/`lookahead` widens the window it hands down/up the chain) — the only difference is
*which model* the literal `--event-time-start`/`--event-time-end` window is pinned to.

## The command

```bash
zhao-dbt-plan \
  --select "mb_events_daily+" \
  --event-time-start "2026-01-10" \
  --event-time-end "2026-01-11" \
  --pretty
```

No `--anchor` here — the window is the Entry Node's (`mb_events_daily`'s) own run window.

Verified output:

```
[layer 0] mb_events_daily [2026-01-10 .. 2026-01-11]
  [layer 1] mb_device_activity_3d [2026-01-08 .. 2026-01-11]
    [layer 2] mb_device_activity_7d_smoothed [2026-01-02 .. 2026-01-12]
```

Reading it top-down:

1. **`mb_events_daily`** (the Entry Node) gets exactly the window you gave it:
   `2026-01-10 .. 2026-01-11`.
2. **`mb_device_activity_3d`** widens that by its own `meta.zhao.lookback: 2, lookahead: 0`:
   `01-10 − 2 = 01-08`, `01-11 + 0 = 01-11` → `2026-01-08 .. 2026-01-11`.
3. **`mb_device_activity_7d_smoothed`** widens Tier 2's window by its own
   `lookback: 6, lookahead: 1`: `01-08 − 6 = 01-02`, `01-11 + 1 = 01-12` →
   `2026-01-02 .. 2026-01-12`.

Compare this to `cascading-window-backfill`'s output for the *identical* `2026-01-10 .. 01-11`
window: there, it's pinned to the deepest model and the widening cascades **upstream**
(narrower windows near the entry, wider near the anchor). Here, it's pinned to the Entry Node and
the same widening formula cascades **downstream**, tier by tier, using each tier's own
`lookback`/`lookahead` — the window each downstream tier needs to cover keeps growing the further
it is from the entry.

## CI

The [`downstream-cascaded-run` workflow](../../.github/workflows/downstream-cascaded-run.yml)
runs on every pull request touching this folder *or* the shared `cascading-window-backfill`
project: it installs `zhao-dbt-plan`, `dbt parse`s the shared project, runs the command above, and
uploads the plan JSON as a workflow artifact.

## Run it yourself

```bash
cd dbt_projects/cascading-window-backfill   # the shared project this example plans
pip install dbt-core dbt-duckdb
export DBT_PROFILES_DIR=.
dbt seed
dbt parse
zhao-dbt-plan --select "mb_events_daily+" \
  --event-time-start "2026-01-10" --event-time-end "2026-01-11" --pretty
```
