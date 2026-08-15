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
| [`dbt_projects/downstream-cascaded-run/`](dbt_projects/downstream-cascaded-run/README.md) | `zhao-dbt-plan` (default) | The same microbatch chain, planned forward from the entry model's own explicit run window — no anchor, contrasted directly with the backfill example above. | Base: [#5](https://github.com/allenhori/zhao-examples/pull/5) |
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

## Contributing

This repo is meant to stay a reliable, permanent demo of the `zhao` tools — every example here has
been verified to actually run, and that guarantee only holds if the set of examples stays small
and deliberately maintained. Forking or cloning it for your own use is very welcome. Pull requests
from outside contributors won't be merged, so please don't spend time on one — if something here
looks wrong, cloning it and checking is faster than waiting on a review.

## License

[Apache 2.0](LICENSE).
