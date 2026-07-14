# Verification

Run narrow checks first, then the full matrix:

```sh
moon test src/report
moon test src/cli --target native
moon check --target js
moon check --target native
moon test
moon info
moon fmt
```

The report tests cover structured JSON escaping, XML/HTML escaping, line and
heatmap rendering, and JSONL-to-Plot-IR conversion. The checked-in JSONL fixture
also supports an end-to-end native CLI smoke test.

Passing these tests proves the finite checked behavior only. It does not prove
statistical confidence intervals, bootstrap correction, filesystem streaming
during a benchmark, or every PlotKind-specific semantic.
