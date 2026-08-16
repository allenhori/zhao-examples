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

## The plan's JSON output driving a real `dbt build` per tier — including the lookahead case

Same JSON-consumption pattern as `cascading-window-backfill`'s own build step, applied to this
forward-cascade plan instead: the workflow's last step reads `target/zhao/dbt_plan.json` with
`jq`, walks its `models` array in `layer` order (upstream tier first), and runs each tier's own
computed window as a real `dbt build --select <model> --event-time-start <...> --event-time-end
<...>`. `zhao-dbt-plan` never executes anything itself — this is what actually turns the plan
into runs.

This scenario is the interesting one for *lookahead* specifically: `mb_device_activity_7d_smoothed`'s
`lookahead: 1` computes a window (`2026-01-02 .. 2026-01-12`) that extends a day **past** the
Entry Node's own explicit end date (`2026-01-11`) — a real instance of a downstream tier needing
to look ahead of the window its upstream was actually run for, not just re-reading the same days
with more lookback. Verified in CI, real batch output:

```
Running: dbt build --select mb_events_daily --event-time-start "2026-01-10" --event-time-end "2026-01-11"
  Batch 1 of 1 OK created batch 2026-01-10 of main.mb_events_daily ..... [OK in 0.11s]
  Done. PASS=1 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=1

Running: dbt build --select mb_device_activity_3d --event-time-start "2026-01-08" --event-time-end "2026-01-11"
  Batch 1 of 3 OK created batch 2026-01-08 of main.mb_device_activity_3d
  Batch 2 of 3 OK created batch 2026-01-09 of main.mb_device_activity_3d
  Batch 3 of 3 OK created batch 2026-01-10 of main.mb_device_activity_3d
  Done. PASS=1 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=1

Running: dbt build --select mb_device_activity_7d_smoothed --event-time-start "2026-01-02" --event-time-end "2026-01-12"
  Batch 1 of 10 OK created batch 2026-01-02 of main.mb_device_activity_7d_smoothed
  ...
  Batch 9 of 10 OK created batch 2026-01-10 of main.mb_device_activity_7d_smoothed
  Batch 10 of 10 OK created batch 2026-01-11 of main.mb_device_activity_7d_smoothed
  Done. PASS=1 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=1
```

`mb_events_daily` only ever ran a batch for `01-10` (its own explicit window), but
`mb_device_activity_7d_smoothed` correctly built a `01-11` batch too — a day genuinely ahead of
what the entry model itself processed, computed from `lookahead: 1` rather than hand-picked. The
chain's dates are fixed in the past (`2026-01-xx`) on purpose: a lookahead-widened window is still
just a fixed historical date this way, not something that depends on, or could run into, whatever
"today" happens to be when this workflow actually executes.

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
