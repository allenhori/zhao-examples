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

More examples land here incrementally — see this repo's own pull request history for how each was
added and verified.

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
