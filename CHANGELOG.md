# Changelog

All notable changes to Mare Mark are documented in this file.

## 0.2.0 - 2026-07-14

- Add fair benchmark timing protocols with shared warmup, seeded balanced
  execution order, asynchronous synchronization hooks, and median-based
  repeated-observation reporting.
- Add complete execution environment snapshots covering CPU, device,
  concurrency, clock, garbage collection, and frequency policy metadata.
- Add environment compatibility checks and JSONL summary propagation for
  reproducible comparisons and downstream reports.
- Add tuning score aggregation, Pareto filtering, GEMM candidate models, and
  regression coverage for runner timing boundaries and reset exclusion.
- Refresh generated public interfaces and localized runner documentation.

## 0.1.0 - 2026-07-14

- Add reproducible differential benchmark execution with sticky contexts.
- Add reference and relational oracles with shrinking and replay artifacts.
- Add subprocess crash isolation, timeouts, and structured execution outcomes.
- Add streaming JSONL sinks and differential HTML reports.
- Add statistical summaries, crossover diagnostics, and tuning data models.
- Add public construction paths and package-level compatibility tests.
- Add native artifact report and replay commands.
