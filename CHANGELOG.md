# Changelog

All notable changes to mare_mark are documented in this file.

## Unreleased

- Migrate to MoonBit 0.10 (`moonc` 0.10 or later is now required).
- Bump `moonbitlang/x` to 0.5.5 and `moonbitlang/async` to 0.22.4.
- Declare the `cli` package with `pkgtype(kind: "executable")` instead of the
  legacy `is-main` option.
- Remove unused package imports (`moonbitlang/async/io`, `moonbitlang/core/json`,
  `moonbitlang/core/string`, `moonbitlang/core/test` where unused), and scope
  `-unused_package` to `cli` and `runner`, whose native-only files use imports
  that are unused on other targets.
- Replace the ambiguous `{}` map literal in `BenchSpec::compile` with
  `Map([])`; reformat sources with the 0.10 formatter. No public API change.
- Qualify package names in blackbox tests (`@experiment.`, `@stats.`,
  `@tune.`, `@tune_gemm.`).
- Documentation rewritten: an API page, a tutorial and a design page for every
  package (13 packages), with derivations of the statistics, the experimental
  design, calibration, seed derivation and the tuning policy, a Typst
  attachment on the percentile bootstrap, and compiled examples. The former
  package reference is folded into the package pages. Chinese and Japanese
  translations are complete.

### Fixed

- `stats.compare_paired` and `experiment.comparator_label` no longer report an
  exact tie as `Faster` / `"A"` at a zero threshold; a tie is `Equivalent` /
  `"Unknown"` for every threshold. A threshold that is `NaN`, infinite or
  negative, or a `NaN` relative delta, now gives `Invalid` / `"Unknown"`
  instead of a classification (#1).
- `runner.validate_protocol` rejects `NaN` and infinite durations
  (`warmup_time_us`, `target_batch_time_us`, `max_sample_time_us`) and a
  non-finite `practical_delta_pct` (#1).
- `stats.summarize` propagates `NaN`: every statistic except `count` is `NaN`
  when the input contains one, instead of an inconsistent summary with
  `min > max`. `filter_outliers` computes its fences from the non-`NaN`
  values and drops `NaN` (#11).

## 0.3.0 - 2026-07-15

- Add deterministic percentile bootstrap intervals for paired measurements,
  with explicit seeds and structured validation errors.
- Add artifact-version metadata to every emitted JSONL event while preserving
  the existing `mmka_1` additive compatibility contract.
- Add regression coverage for event fan-out, JSONL contracts, CLI error paths,
  and minimized replayable runner failures.
- Expand CI with JS and native test matrices, native CLI smoke tests, and an
  executable-line coverage budget.
- Refresh generated interfaces and synchronized English, Chinese, and Japanese
  release documentation.

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
