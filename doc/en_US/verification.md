# Verification

Run narrow checks first, then the full matrix:

```sh
moon test src/report
moon test src/cli --target native
moon test --target js
moon test --target native
moon check --target js
moon check --target native
moon test
moon coverage analyze
moon info
moon fmt
```

The report tests cover structured JSON escaping, XML/HTML escaping, line and
heatmap rendering, and JSONL-to-Plot-IR conversion. The checked-in JSONL fixture
also supports end-to-end native report and replay dry-run smoke tests. Event
tests verify the `mmka_1` marker, sink fan-out, and replayable minimized failures.

The stats tests verify deterministic percentile bootstrap bounds and invalid
configuration handling. They do not prove BCa correction, hierarchical
resampling, filesystem streaming during a benchmark, or every PlotKind-specific
semantic. CI caps uncovered executable lines at 360 to prevent silent coverage
regression; the budget is not a percentage or a substitute for risk-based tests.
