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

## The plan's JSON output actually driving `dbt build` — not just an artifact

`zhao-dbt-plan` never executes anything itself — it only computes and writes a plan. The
[workflow](../../.github/workflows/cascading-window-backfill.yml)'s last step is what turns that
plan into real runs: it reads `target/zhao/dbt_plan.json` with `jq`, walks its `models` array in
`layer` order (upstream tier first), and for each model runs

```bash
dbt build --select <model> --event-time-start <that model's computed event_time_start> --event-time-end <that model's computed event_time_end>
```

— the plan's own computed window for each tier, literally, not a human reading the JSON and
retyping the dates. Verified locally: all three tiers build successfully in the plan's own
computed windows (`mb_events_daily` for `2026-01-02..01-12`, `mb_device_activity_3d` for
`2026-01-04..01-12`, `mb_device_activity_7d_smoothed` for `2026-01-10..01-11`), each depending on
the previous tier's output already being built with its own wider window.

**A real thing this surfaced**: actually running `dbt build` (as opposed to only `dbt
parse`/`dbt compile`, which this repo's examples had only ever done before) exposed a genuine
misconfiguration in `mb_device_activity_3d` — its `event_time` config pointed at `event_at`
(the upstream's column name), but this model's own `select` aliases that column to
`activity_date` and never exposes an `event_at` column of its own. dbt's microbatch execution
needs `event_time` to name a column the model's *own* output actually has; this compiled and
`dbt parse`d fine either way, since batch filtering only runs against a real batch context, but
failed the instant a real `dbt build` tried to filter this model's own output by a column that
doesn't exist. Fixed by pointing `event_time` at `activity_date`, the column this model actually
produces — the `lookback`/`lookahead` cascade math and every other example in this repo is
unaffected, since `zhao-dbt-plan` only ever read `meta.zhao`, never `event_time`'s value.

## The `--html` report — what it adds over the `--pretty` ASCII tree

`--pretty` (used above) prints a plain-text tree to the job log — useful for a quick read, but it's
gone the moment the log scrolls past it. `--html` produces a self-contained, interactive report —
pan/zoom the tier graph, hover a model for its exact computed window and `lookback`/`lookahead` —
committed in this repo as [`dbt_plan_report.html`](dbt_plan_report.html), a real file you can open
directly. `zhao-dbt-plan --html` writes it to a timestamped filename under
`target/zhao/dbt-plan/`, not a fixed path, so the CI workflow diffs its *content* (not the
filename) against the committed copy and fails the job if they differ — verified locally that the
export is fully deterministic (byte-identical across separate runs given the same plan), so this
is a real staleness check, not decorative.

## Triggering a real, on-demand backfill

Every run above happens automatically on a pull request touching this folder — but a real backfill
is normally something someone decides to run for a specific date, on demand, not something that
just happens to run because a file changed. The
[workflow](../../.github/workflows/cascading-window-backfill.yml) also accepts a manual
`workflow_dispatch` trigger with one input, `anchor_date`, so anyone can actually run this against
a date of their choosing from the Actions tab (`Run workflow` → pick a date → `Run workflow`) and
get a real Action run, with the same JSON plan and `--html` report attached as downloadable
artifacts, as the result — not a screenshot standing in for one.

## Run it yourself

```bash
cd dbt_projects/cascading-window-backfill
pip install dbt-core dbt-duckdb
export DBT_PROFILES_DIR=.
dbt seed
dbt parse   # zhao-dbt-plan reads target/manifest.json
zhao-dbt-plan --select "mb_events_daily+" --anchor mb_device_activity_7d_smoothed \
  --event-time-start "2026-01-10" --event-time-end "2026-01-11" --pretty --html

# Drive real dbt build commands from the plan's own JSON output:
jq -r '.models | sort_by(.layer) | .[] | "\(.name)\t\(.event_time_start)\t\(.event_time_end)"' \
  target/zhao/dbt_plan.json |
while IFS=$'\t' read -r name start end; do
  dbt build --select "$name" --event-time-start "$start" --event-time-end "$end"
done
```
