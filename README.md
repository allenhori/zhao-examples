# zhao-examples

Runnable, CI-verified example projects for the [`zhao`](https://github.com/allenhori/zhao-cli)
family of dbt tooling:

- [`zhao-cli`](https://github.com/allenhori/zhao-cli) — a breaking-change gate for dbt.
- [`zhao-dbt-plan`](https://github.com/allenhori/zhao-dbt-plan) — a static cascading time-window
  planner for dbt microbatch models.
- [`zhao_dbt_utils`](https://github.com/allenhori/zhao_dbt_utils) — a small dbt macro package,
  including `wref()` ("windowed ref").

Every example here is a real DuckDB dbt project with its own GitHub Actions workflow. Nothing in
this repo is a mockup: each workflow actually installs the relevant tool, actually runs it against
the project, and the READMEs describe output that was verified locally before being committed —
not output someone hoped it would produce.

## Examples

| Example | Tool | What it shows | Key PRs |
|---|---|---|---|
| [`dbt_projects/breaking-change-gate/`](dbt_projects/breaking-change-gate/README.md) | `zhao-cli` (`check`, `diff`, `lineage`) | CI fails a pull request when a compiled-SQL change removes a column an active downstream model depends on; `zhao diff`'s JSON output drives a `dbt build` of only the actually-impacted models (contrasted against dbt's own blunter `state:modified+`); `zhao diff` contrasted against `check`'s exit-code contract; a committed, interactive `zhao lineage --html` report. | Base: [#2](https://github.com/allenhori/zhao-examples/pull/2) · JSON→build: [#7](https://github.com/allenhori/zhao-examples/pull/7) · `lineage --html`: [#8](https://github.com/allenhori/zhao-examples/pull/8) · `check` vs `diff`: [#9](https://github.com/allenhori/zhao-examples/pull/9) · **live demo (open):** [#3](https://github.com/allenhori/zhao-examples/pull/3) (an intentional breaking change `zhao check` actually fails on) |
| [`dbt_projects/cascading-window-backfill/`](dbt_projects/cascading-window-backfill/README.md) | `zhao-dbt-plan` (`--anchor`) | Given an explicit backfill window on one upstream model, the planner computes the correctly widened window for every downstream tier of a microbatch chain — and its JSON plan output literally drives a `dbt build --select <model> --event-time-start/--event-time-end` per tier. A committed, interactive `--html` plan report. | Base: [#4](https://github.com/allenhori/zhao-examples/pull/4) · JSON→build: [#7](https://github.com/allenhori/zhao-examples/pull/7) · `--html` report: [#10](https://github.com/allenhori/zhao-examples/pull/10) |
| [`dbt_projects/downstream-cascaded-run/`](dbt_projects/downstream-cascaded-run/README.md) | `zhao-dbt-plan` (default) | The same microbatch chain, planned forward from the entry model's own explicit run window — no anchor, contrasted directly with the backfill example above; its JSON plan output drives a real `dbt build` per tier too, including a genuine lookahead case (a downstream tier's computed window reaching a day past the entry model's own explicit end date). | Base: [#5](https://github.com/allenhori/zhao-examples/pull/5) · JSON→build: [#18](https://github.com/allenhori/zhao-examples/pull/18) |
| [`dbt_projects/wref-windowed-ref/`](dbt_projects/wref-windowed-ref/README.md) | `zhao_dbt_utils` (`wref()`, package install, boundary helpers) | A rolling-window model shown three ways — plain `ref()`, standalone `wref()`, package-installed `zhao_utils.wref()`, and hand-written `zhao_window_start()`/`zhao_window_end()` boundary helpers — with the compiled SQL proving `ref()` silently under-computes the window and every `wref()` variant reads the correct one. | Base: [#6](https://github.com/allenhori/zhao-examples/pull/6) · Package install + boundary helpers: [#11](https://github.com/allenhori/zhao-examples/pull/11) |

**Live demo PRs, open on purpose** — each is a real, unmerged change whose CI output is the actual
demo, not a screenshot standing in for one:
- [#3](https://github.com/allenhori/zhao-examples/pull/3) — a genuine breaking change (a column
  removal an active downstream model depends on) that `zhao check` catches and fails on.
- [#12](https://github.com/allenhori/zhao-examples/pull/12) — a live, non-breaking change showing
  `zhao diff`'s JSON driving a build of only the actually-impacted models, contrasted against
  `state:modified+`.

**A real, manually-triggered backfill run** —
[cascading-window-backfill's workflow](.github/workflows/cascading-window-backfill.yml) accepts a
`workflow_dispatch` trigger for an on-demand backfill against any date, from the Actions tab.
[This run](https://github.com/allenhori/zhao-examples/actions/runs/31875630004) is a real example
— `anchor_date: 2026-01-08`, plan computed and `dbt build` actually run live, with the JSON plan
and `--html` report attached as downloadable artifacts.

Each example folder is self-contained and runnable on its own (`cd` into it, install the tool it
demonstrates, follow its README). The "Key PRs" column above is the fastest way to see exactly how
and where a specific capability was added, with real CI runs attached to each one.

## PR-by-PR breakdown

The table above tells you which PR to open for a given capability; this section says, PR by PR,
what each one actually demonstrates and why it exists. Grouped by example, in the order each
capability was added.

### `breaking-change-gate` ([`zhao-cli`](https://github.com/allenhori/zhao-cli))

- **[#1](https://github.com/allenhori/zhao-examples/pull/1)** (closed, superseded by #2) — first
  pass at the example; closed in favor of #2 once the marts layer needed for a real breaking
  change was added in the same PR instead of a follow-up.
- **[#2](https://github.com/allenhori/zhao-examples/pull/2)** — the base project (2 seeds → 2
  staging models → 2 mart models) and the CI workflow that installs `zhao-cli`, compiles the
  project, and runs `zhao check --against <base branch>` on every PR. Establishes the gate itself.
- **[#3](https://github.com/allenhori/zhao-examples/pull/3)** (open — live demo, not meant to be
  merged) — removes `last_name` from `stg_customers`, which `dim_customers` actively reads
  (directly and through a computed `full_name` column). dbt itself compiles fine; `zhao check`
  correctly fails the job with two `column-removed-with-active-references` findings. This is the
  gate's whole reason to exist, running for real.
- **[#7](https://github.com/allenhori/zhao-examples/pull/7)** — the JSON-consumption step: after
  `zhao check` passes, `zhao diff --format json` is parsed with `jq` into the changed-or-impacted
  model list, which drives a real `dbt build --select <that list>` into an isolated `staging`
  schema — the recommendation actually gets acted on, not just printed. Also adds the
  `state:modified+` side-by-side comparison.
- **[#8](https://github.com/allenhori/zhao-examples/pull/8)** — `zhao lineage`, both `--text` and
  its actual default `--html` mode: a structural upstream/downstream query with no Baseline or
  git diff involved at all, contrasted against `check`/`diff`'s Baseline comparison. The generated
  interactive report is committed, and CI fails if it drifts from a fresh regeneration.
- **[#9](https://github.com/allenhori/zhao-examples/pull/9)** — `zhao diff` run right alongside
  `zhao check` (identical engine, always exits `0`) so the exit-code contrast between the CI gate
  and the dev-time inspection command is visible in the same job log, against the same breaking
  change.
- **[#12](https://github.com/allenhori/zhao-examples/pull/12)** (open — live demo, not meant to be
  merged) — a genuinely additive, non-breaking change (`email_lower` added to `stg_customers`,
  nothing downstream reads it yet). `zhao-check` passes and builds only 1 model; `state:modified+`
  is shown separately at 3. The `lineage` job is expected to fail here — deliberately, since this
  branch makes the committed lineage report stale — which is the drift check working as designed,
  not a bug.
- **[#14](https://github.com/allenhori/zhao-examples/pull/14)** (open, pending review) — turns the
  #7/#12 side-by-side lists into a computed savings line instead of two lists to eyeball and
  subtract: `zhao built N model(s) ... state:modified+ would have built M model(s) ... N fewer
  models rebuilt (X% less)`.

### `cascading-window-backfill` ([`zhao-dbt-plan`](https://github.com/allenhori/zhao-dbt-plan), `--anchor`)

- **[#4](https://github.com/allenhori/zhao-examples/pull/4)** — a real 3-tier microbatch chain
  with `lookback`/`lookahead` config per tier, plus the `--anchor` invocation: given an explicit
  backfill window pinned to the deepest model, the planner computes the correctly widened window
  for every tier above it.
- **[#7](https://github.com/allenhori/zhao-examples/pull/7)** — same JSON-consumption pattern as
  the breaking-change-gate half of this PR: the plan's JSON output drives a per-tier `dbt build
  --select <model> --event-time-start/--event-time-end`, in the plan's own layer order.
- **[#10](https://github.com/allenhori/zhao-examples/pull/10)** — `zhao-dbt-plan --html`, its
  interactive report format (the existing example had only used `--pretty`/JSON). Committed and
  drift-checked in CI the same way as `zhao lineage --html` in #8.

### `downstream-cascaded-run` ([`zhao-dbt-plan`](https://github.com/allenhori/zhao-dbt-plan), default mode)

- **[#5](https://github.com/allenhori/zhao-examples/pull/5)** — the same microbatch chain from
  `cascading-window-backfill`, run through `zhao-dbt-plan`'s default (no `--anchor`) mode instead:
  an explicit window at the entry model cascades forward, not upstream from an anchor. Exists
  specifically to be read side by side with #4's output on the identical chain.
- **[#18](https://github.com/allenhori/zhao-examples/pull/18)** — same JSON-consumption pattern as
  #7, applied to this forward-cascade plan: each tier's computed window drives a real `dbt build`.
  Specifically exercises the lookahead case — `mb_device_activity_7d_smoothed`'s `lookahead: 1`
  computes a window reaching a day past the entry model's own explicit end date (`01-11` vs.
  `01-12`), and CI shows a real `01-11` batch actually getting built for it. Dates fixed safely in
  the past so a lookahead-widened window stays a fixed historical date rather than depending on
  whatever "today" is when the workflow runs.

### `wref-windowed-ref` ([`zhao_dbt_utils`](https://github.com/allenhori/zhao_dbt_utils), `wref()`)

- **[#6](https://github.com/allenhori/zhao-examples/pull/6)** — proves, with real compiled SQL and
  real query results, that plain `ref()` silently under-computes a rolling-window microbatch
  model's window while `wref()` (installed standalone) computes the correct one — same
  `meta.zhao.lookback` config, one line different at the call site, and a different (wrong vs.
  right) number in the output.
- **[#11](https://github.com/allenhori/zhao-examples/pull/11)** — two more ways to use the same
  boundary logic: `zhao_utils.wref()` via a real `dbt deps` package install (pinned version,
  namespaced call) instead of a copy-pasted macro file, and `zhao_window_start()`/`zhao_window_end()`
  for hand-writing a custom `WHERE` clause when `wref()`'s fixed shape doesn't fit. All three
  variants verified to produce byte-identical compiled SQL and output rows.

### Repo-wide

- **[#13](https://github.com/allenhori/zhao-examples/pull/13)** — updates this README's examples
  table to mention the capabilities added in #7–#11, after they'd landed.

## Contributing

This repo is meant to stay a reliable, permanent demo of the `zhao` tools — every example here has
been verified to actually run, and that guarantee only holds if the set of examples stays small
and deliberately maintained. Forking or cloning it for your own use is very welcome. Pull requests
from outside contributors won't be merged, so please don't spend time on one — if something here
looks wrong, cloning it and checking is faster than waiting on a review.

## License

[Apache 2.0](LICENSE).
