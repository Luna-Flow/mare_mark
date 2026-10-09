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
- Documentation brought to the Luna-Flow manual standard: the overview has
  install, pages, exported-item and validation sections; every API page has
  purpose and importing sections; every tutorial opens with a task table;
  every design page states its constraints.
- Documentation logic review: the stats design now derives the actual
  coverage of the percentile bootstrap interval for small samples (87.5 % for
  a nominal 95 % with seven pairs), corrects the coverage-error orders and the
  support of the resampled median for even samples, and documents the
  threshold rule of `compare_paired` and `comparator_label`. The tune pages
  document that the `exhaustive_scores` policy is the raw minimum (#12) and
  that ids are compared with MoonBit's length-first `String` order. The pages
  describe the fixed behaviour listed below. Smaller corrections in the runner (calibration
  gap identity, `NaN` protocol values), generator, event and report designs.

### Added

- `env_detect` package: `detect()` builds a `model.EnvironmentSnapshot` from
  the running process (execution target, runtime, GC, OS, hostname, CPU model
  with its logical core count, UTC timestamp, git revision from `GITHUB_SHA` /
  `CI_COMMIT_SHA` / `GIT_COMMIT` or `git rev-parse HEAD` on native, toolchain
  from `MARE_MARK_TOOLCHAIN`, and a fresh run id from `new_run_id`).
  `concurrency`, the benchmark's own parallelism, is never detected. Fields
  that cannot be detected are `"unknown"` (or a documented default) and are
  listed in `DetectedEnvironment.undetected`; every field can be overridden by
  a labelled argument (#19).
- The README example uses `env_detect.detect` instead of a hand-written
  environment.
- `report.document_from_jsonl` compares every implementation with a baseline
  at every scale of every case (#18). Observations are paired by
  `(case, scale, block_id)` over the confirmatory, valid, kept observations
  the plot uses; blocks without exactly one observation of both
  implementations are dropped and counted. The recorded `outlier_policy` is
  applied to the paired deltas (never to each implementation's raw times),
  and `stats.compare_paired_with_bootstrap` decides with the recorded
  `practical_delta_pct`, a 95 % percentile bootstrap with 10000 resamples and
  a per-row seed derived from the run seed, case, scale, baseline and
  candidate. Records without a protocol or seed use `report_only`, 1 % and
  seed 0, and the report says so. Fewer than 3 usable blocks, a missing
  baseline, unrecorded `block_id`s and bootstrap errors give `Unknown` /
  `Invalid` rows with a reason. New optional `baseline?` argument (default:
  the first implementation of each case); an unknown id is an error. A
  malformed `protocol` or `seed` in the summary is now an error.
- `ir_model`: `ComparisonDecision`, `PairedEstimate`, `DeltaInterval`,
  `ComparisonRow` and `ComparisonReport`; `PlotDocument.comparisons`, set by
  the new optional `PlotDocument::new(..., comparisons~)`. `report.plot_json`
  writes them under `comparisons`.
- `report.html` renders a "Comparisons" section before the plots: medians,
  relative delta, bootstrap interval, a labelled decision tag, blocks used /
  incomplete / outliers, the row seed and a note stating the threshold,
  outlier policy, confidence and resamples with their source.
  `report.comparisons_text` gives the same table as aligned plain text.
- `mare-mark report` prints the comparison table (to stderr when the HTML goes
  to stdout, `--quiet` suppresses it) and accepts `--baseline <id>`.
  `cli.render_jsonl_report` takes an optional `baseline?`.
- `testdata/report/compare.jsonl`: a hierarchical-design record with a
  protocol, several confirmatory blocks per scale, an incomplete block and a
  paired-delta outlier; the CI smoke test renders it with `--baseline`.

### Fixed

- `mare-mark report --baseline` no longer takes the next option as its
  value: `--baseline --quiet` (or `--baseline -`) is the usage error
  `option '--baseline' requires an implementation id`, as is an empty
  `--baseline=`; use `--baseline=<id>` for an id that starts with `-`. When
  several usage errors occur, the first one is reported (#28).
- Report comparisons keep every pair under `ReportOnly`. A pair whose paired
  delta is `NaN` was always removed and counted as an outlier, because
  membership was tested with `NaN != NaN`; it now reaches the bootstrap,
  which makes the row `Invalid` with its reason (#29).
- `mare-mark report` prints its elapsed time with three decimals of a
  millisecond (`elapsed: 11.127ms`), the resolution of the microsecond
  clock, instead of the raw `Double` text with floating-point noise
  (`11.126833000000001ms`) (#25).
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
- `mare-mark report` prints its elapsed time in milliseconds; it printed
  microseconds labelled `ms` (#2).
- `mare-mark replay --dry-run` without an artifact reports
  `replay requires an input artifact` and exits with `2` instead of exiting
  `0` silently (#9).
- `tune.seeded_order` finalizes its seeded FNV-1a key with the SplitMix64
  output finalizer before sorting. Unmixed keys kept ids that differ only in their
  last characters next to each other, so a prefix was far from a random
  subset. **The order produced for a given seed changes**: subsets recorded
  with an earlier version are not reproduced by this one (#10).
- `experiment.crossover_from_labels` sorts the (scale, label) pairs with
  `ScaleDomain.compare` before looking for transitions, so an unsorted domain
  no longer turns a single crossover into `NonMonotonic` or a wrong boundary.
  The evidence lists the labels in sorted order (#5).
- JSONL observations carry `setup_timing` (`excluded_from_measurement` or
  `included_in_measurement`), and validation and `validation_failure` lines
  carry the `reason` of every status that has one. Both fields are additive
  within `mmka_1`; readers that ignore unknown fields are unaffected (#8).
- `model.protocol_identity` covers every `RunProtocol` field, including the
  calibration, the `BalancedBlocks` seed and the optional warm-up time; it
  covered only `warmup_iterations`, `confirmatory_samples` and
  `practical_delta_pct`, so different protocols shared an identity. **The
  identity format changes** from `mmkp_1:<w>:<c>:<d>` to
  `mmkp_2:<16 hex digits>`, the 64-bit FNV-1a digest of the new
  `model.protocol_canonical_encoding`; `ProtocolVersion::V2` is added and `V1`
  is `Deprecated`. `artifact_identity` values change with it.
  `ExperimentDesign`, `BatchPolicy`, `OutlierPolicy` and `ValidationCoverage`
  gain `text()`, the snake_case tags used by the encoding (#3).
- `RunSummary.run_id` distinguishes separate runs. **The run id format
  changes** from `<protocol identity>:<case id>` to
  `<case id>|<protocol identity>|<seed>|<provenance run_id>|<provenance timestamp>`
  (built by the new `model.run_identity`, which escapes `%` and `|` in the
  free-text parts), so runs with a different seed, provenance run id or
  timestamp no longer share an id (#3).
- JSONL `summary` events carry `protocol_identity`, `seed` (a decimal string)
  and a `protocol` object with every protocol field, so a record can be
  audited and re-analysed; `event.protocol_from_json` decodes the object back
  into the exact `RunProtocol` and `event.protocol_json` encodes it.
  `RunSummary` gains `protocol` and `seed` (optional labelled arguments of
  `RunSummary::new`). The fields are additive within `mmka_1`; readers that
  ignore unknown fields are unaffected (#3).
- `runner.run` no longer ignores `RunProtocol.experiment_design`,
  `validation_coverage` and the fixture's setup frequency and workspace scope
  (#4):
  - `MultipleDatasetsSingleMeasurement` materializes a fresh dataset for every
    block and `HierarchicalDatasetsAndRepeats` one for every
    `repeats_per_dataset` consecutive blocks. `dataset_id` is unique within a
    run (`scale_index * datasets_per_scale + index`); warmup and calibration
    run once per scale on its first dataset. `FixedDatasetRepeatedMeasurements`
    produces the same datasets, seeds and events as before.
  - New optional `RunProtocol::new(..., repeats_per_dataset~)` (default `1`).
    `validate_protocol` rejects a value below `1`
    (`InvalidInteger("repeats_per_dataset", _)`), sample counts it does not
    divide under the hierarchical design (`IndivisibleSamples`), and any value
    other than `1` under the other designs (`UnusedRepeatsPerDataset`). The
    `RegressionGate` preset uses `5`. `repeats_per_dataset` is part of
    `protocol_canonical_encoding`, and so of `protocol_identity` (every
    `mmkp_2` identity changes, since the encoding gains
    `;repeats_per_dataset=<r>`), and of the `protocol` object recorded in JSONL
    summaries; `protocol_from_json` reads a record without the key as `1`.
  - `ConfirmatoryOnly` validates only the datasets measured by confirmatory
    blocks; `EveryDataset` validates every measured dataset; `EveryMeasurement`
    also validates, outside the timed region, before every exploratory and
    confirmatory batch on the input and prepared value that batch uses, then
    resets it. These validations carry `Validation.measurement`, and
    `RunSummary.measurement_validation_count` counts them (they are included in
    `validation_count`).
  - Long-lived setup (`PerRun`, `PerDataset`, `PerImplementation`) is prepared
    once per (dataset, implementation) and cached across that dataset's
    warmup, calibration and blocks. `PerRun` is rejected with
    `BenchConfigError::PerRunSetupWithMultipleDatasets` when the case has more
    than one dataset: by `BenchSpec::compile` (counting scales, or the
    datasets of the new optional `protocol~` argument) and by `run`, which
    raises `RunConfigError`.
  - JSONL observations carry `setup_frequency` and `workspace_scope`;
    measurement validations carry `validation_scope: "measurement"`,
    `repetition_id` and `block_id`; summaries carry
    `measurement_validation_count`. All are additive within `mmka_1`.
    `Observation::new` takes optional `setup_frequency~` and
    `workspace_scope~`, and `Validation::new` / `Validation::detailed` an
    optional `measurement~`.
  - `outlier_policy` and `practical_delta_pct` remain analysis-time settings
    and do not change what the runner measures.
- `report.document_from_jsonl` plots only confirmatory observations.
  Observations of any other phase (`exploratory`, or a phase the reader does
  not know) are left out of the timing plot and counted in its caption; a
  record without `phase` predates the field and counts as confirmatory. Before,
  exploratory and confirmatory times were plotted as one series (#7).
- The scaling plot's x value is the dataset's scale instead of `dataset_id`.
  There is one plot per case and one point per (implementation, scale): the
  median per-iteration time of the confirmatory observations at that scale,
  pooled over every dataset and repetition that shares it (`interval_kind` is
  now `median` instead of `raw`). Scales that all parse as finite numbers are
  placed on a linear axis in numeric order; other scales are categorical in
  order of first appearance. Records without `scale` fall back to
  `dataset_id`, and the axis label says so (#7).
- JSONL observations carry `scale`, the scale text the validation events
  already had. The field is additive within `mmka_1` and omitted when no scale
  text was recorded. `model.Observation` has a `scale_text` field and
  `Observation::new` an optional `scale_text?` argument, so existing calls
  still compile (#7).
- `ir_model.Plot` has `x_axis` (`AxisScale::Categorical` or `Linear`),
  `x_label` and `note`, set through optional `Plot::new` arguments.
  `report.plot_json` writes them, `plot_svg` draws the x-axis label and
  `html` shows the note in the figure caption (#7).
- The `single_step(...).against_equal(...)` builder records an empty scale
  text instead of the placeholder `"<scale>"`, so its validation events carry
  `"scale":""` and its observations no `scale`; the report then plots such
  runs by `dataset_id` instead of pooling every dataset under one `<scale>`
  category. Use `BenchSpec::advanced` to record real scale text (#7).

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
