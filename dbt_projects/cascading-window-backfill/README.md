# cascading-window-backfill

A DuckDB dbt project with a real 3-tier microbatch chain, used to demonstrate
[`zhao-dbt-plan`](https://github.com/allenhori/zhao-dbt-plan)'s `--anchor` mode: given an explicit
backfill window on one specific model, the planner computes the correctly widened window every
*upstream* tier of the chain needs to cover to support it — without you doing that arithmetic by
hand, and without the planner ever executing anything itself (it only computes and prints/writes a
plan).

This project is also used by the [`downstream-cascaded-run`](../downstream-cascaded-run/README.md)
example, which runs the *same* chain through `zhao-dbt-plan`'s other mode (no `--anchor`) — see
that example's README for the direct contrast.

## The chain

```
mb_events_daily                    (Tier 1 / Entry Node, daily microbatch, no meta.zhao)
        │
        ▼
mb_device_activity_3d              (Tier 2, meta.zhao: lookback 2, lookahead 0)
        │
        ▼
mb_device_activity_7d_smoothed     (Tier 3, meta.zhao: lookback 6, lookahead 1)
```

- **Tier 1** (`mb_events_daily`) is a daily dbt microbatch model reading raw events from a seed.
  It's the chain's Entry Node — nothing upstream of it is also microbatch, so it has no
  `meta.zhao` block.
- **Tier 2** (`mb_device_activity_3d`) computes a 3-day trailing event count per device.
  `meta.zhao.lookback: 2` records that a correct read of Tier 1 needs 2 extra days behind this
  model's own batch window.
- **Tier 3** (`mb_device_activity_7d_smoothed`) computes a 7-day trailing average of Tier 2's
  count, with a 1-day-ahead smoothing pass. `meta.zhao.lookback: 6, lookahead: 1` records what a
  correct read of Tier 2 needs.

## The backfill scenario

Say Tier 3 (`mb_device_activity_7d_smoothed`) needs to be backfilled for a single day,
`2026-01-10`. `zhao-dbt-plan --anchor` pins that literal window to Tier 3 specifically, and
cascades the correctly widened window to everything upstream:

```bash
zhao-dbt-plan \
  --select "mb_events_daily+" \
  --anchor mb_device_activity_7d_smoothed \
  --event-time-start "2026-01-10" \
  --event-time-end "2026-01-11" \
  --pretty
```

Verified output:

```
[layer 0] mb_events_daily [2026-01-02 .. 2026-01-12]
  [layer 1] mb_device_activity_3d [2026-01-04 .. 2026-01-12]
    [layer 2] mb_device_activity_7d_smoothed [2026-01-10 .. 2026-01-11]
```

Reading it bottom-up, the way the cascade actually computes it:

1. **Tier 3** gets exactly the anchored window: `2026-01-10 .. 2026-01-11`.
2. **Tier 2** widens that by Tier 3's own `lookback: 6, lookahead: 1`:
   `01-10 − 6 = 01-04`, `01-11 + 1 = 01-12` → `2026-01-04 .. 2026-01-12`.
3. **Tier 1** widens Tier 2's window by Tier 2's own `lookback: 2, lookahead: 0`:
   `01-04 − 2 = 01-02`, `01-12 + 0 = 01-12` → `2026-01-02 .. 2026-01-12`.

Each tier's window is only as wide as its own downstream consumer's `lookback`/`lookahead`
actually requires — this is the "genuinely non-trivial cascading math" the whole tool exists to
compute correctly instead of by hand.

## CI

The [`cascading-window-backfill` workflow](../../.github/workflows/cascading-window-backfill.yml)
runs on every pull request touching this folder: it installs `zhao-dbt-plan`, `dbt parse`s the
project, runs the exact `--anchor` command above, and uploads the JSON plan
(`target/zhao/dbt_plan.json`) as a workflow artifact alongside the `--pretty` tree printed to the
job log.

## Run it yourself

```bash
cd dbt_projects/cascading-window-backfill
pip install dbt-core dbt-duckdb
export DBT_PROFILES_DIR=.
dbt seed
dbt parse   # zhao-dbt-plan reads target/manifest.json
zhao-dbt-plan --select "mb_events_daily+" --anchor mb_device_activity_7d_smoothed \
  --event-time-start "2026-01-10" --event-time-end "2026-01-11" --pretty
```
