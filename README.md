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
| [`dbt_projects/breaking-change-gate/`](dbt_projects/breaking-change-gate/README.md) | `zhao-cli` | CI fails a pull request when a compiled-SQL change removes a column an active downstream model depends on. |
| [`dbt_projects/cascading-window-backfill/`](dbt_projects/cascading-window-backfill/README.md) | `zhao-dbt-plan` (`--anchor`) | Given an explicit backfill window on one upstream model, the planner computes the correctly widened window for every downstream tier of a microbatch chain. |
| [`dbt_projects/downstream-cascaded-run/`](dbt_projects/downstream-cascaded-run/README.md) | `zhao-dbt-plan` (default) | The same kind of microbatch chain, planned forward from an entry model's own explicit run window — no anchor, contrasted directly with the backfill example. |
| [`dbt_projects/wref-windowed-ref/`](dbt_projects/wref-windowed-ref/README.md) | `zhao_dbt_utils` (`wref()`) | A rolling-window model shown two ways — plain `ref()` vs `wref()` — with the compiled SQL from both, side by side, proving `ref()` silently under-reads the window and `wref()` reads the correct one. |

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
