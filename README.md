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

| Example | Tool | What it shows |
|---|---|---|
| [`dbt_projects/breaking-change-gate/`](dbt_projects/breaking-change-gate/README.md) | `zhao-cli` (`check`, `diff`, `lineage`) | CI fails a pull request when a compiled-SQL change removes a column an active downstream model depends on; `zhao diff`'s JSON output drives a `dbt build` of only the actually-impacted models (contrasted against dbt's own blunter `state:modified+`); `zhao diff` contrasted against `check`'s exit-code contract; a committed, interactive `zhao lineage --html` report. |
| [`dbt_projects/cascading-window-backfill/`](dbt_projects/cascading-window-backfill/README.md) | `zhao-dbt-plan` (`--anchor`) | Given an explicit backfill window on one upstream model, the planner computes the correctly widened window for every downstream tier of a microbatch chain — and its JSON plan output literally drives a `dbt build --select <model> --event-time-start/--event-time-end` per tier. A committed, interactive `--html` plan report. |
| [`dbt_projects/downstream-cascaded-run/`](dbt_projects/downstream-cascaded-run/README.md) | `zhao-dbt-plan` (default) | The same microbatch chain, planned forward from the entry model's own explicit run window — no anchor, contrasted directly with the backfill example above. |
| [`dbt_projects/wref-windowed-ref/`](dbt_projects/wref-windowed-ref/README.md) | `zhao_dbt_utils` (`wref()`, package install, boundary helpers) | A rolling-window model shown three ways — plain `ref()`, standalone `wref()`, package-installed `zhao_utils.wref()`, and hand-written `zhao_window_start()`/`zhao_window_end()` boundary helpers — with the compiled SQL proving `ref()` silently under-computes the window and every `wref()` variant reads the correct one. |

See this repo's own pull request history for how each example was added and verified. A PR
titled `DEMO: ...` may be open at any time, left unmerged on purpose, as a live instance of one
example's CI output against a real change.

Each example folder is self-contained and runnable on its own (`cd` into it, install the tool it
demonstrates, follow its README).

## Contributing

This repo is meant to stay a reliable, permanent demo of the `zhao` tools — every example here has
been verified to actually run, and that guarantee only holds if the set of examples stays small
and deliberately maintained. Forking or cloning it for your own use is very welcome. Pull requests
from outside contributors won't be merged, so please don't spend time on one — if something here
looks wrong, cloning it and checking is faster than waiting on a review.

## License

[Apache 2.0](LICENSE).
