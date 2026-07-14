# `runner` Tutorial

1. Create a `Fixture` with materialize, fingerprint, clone, prepare, and reset callbacks.
2. Register at least one `Implementation`.
3. Define an `OutputSink` that prevents result elimination.
4. Build a `DifferentialCase` with ordered scales.
5. Pass a `RunProtocol`, `EnvironmentSnapshot`, and `ObservationSink` to `run_case`.
6. Preserve emitted observations before computing summaries.

Use distinct runs for JS and native targets. Their elapsed values are not a
single comparable population.

