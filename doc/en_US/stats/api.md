# `stats` API

`stats` provides descriptive summaries and practical paired decisions.

- `summarize` returns count, extrema, mean, median, MAD, quartiles, IQR, and population standard deviation.
- `paired_deltas` subtracts paired baseline values from candidate values.
- `compare_paired` returns relative median delta, speedup, an interquartile interval, decision, and valid sample count.
- `bootstrap_interval` returns a deterministic percentile interval for an explicit seed, resample count, confidence level, and interval mode.
- `compare_paired_with_bootstrap` applies that interval to paired baseline/candidate measurements.
- `filter_outliers` applies report-only, Tukey-fence, or MAD-trim policy.
- `is_faster` recognizes the `Faster` decision.

Bootstrap functions return `Result`; `BootstrapError` distinguishes empty
samples, mismatched pairs, invalid configuration, and non-finite values.

See `src/stats/pkg.generated.mbti` for exact signatures.

## Data contract

Statistics consume finite numeric observations that already passed protocol
validation. Pairing is positional: baseline[i] and candidate[i] must represent
the same dataset, repetition, block, and phase. Align keys before calling the
functions; do not sort two vectors independently.

```moonbit nocheck
let summary = @stats.summarize(values)
let decision = @stats.compare_paired(
  "baseline",
  "candidate",
  baseline,
  candidate,
  2.0,
  @model.confirmatory_interval(),
)
```

`SummaryStats` is descriptive rather than inferential. It includes count, extrema,
mean, median, MAD, quartiles, IQR, and population standard deviation. The
median is the default center for skewed benchmark data; mean remains useful
for diagnosing long tails.

## Paired decisions

`paired_deltas` computes candidate minus baseline for each aligned pair.
`compare_paired` reports relative median delta, speedup, an interquartile
interval, a decision, and valid sample count. The practical threshold is an
explicit policy input; it is not inferred from noise.

`Decision::Faster` is positive only when the direction and threshold agree.
`is_faster` is a convenience predicate for dashboards, not a replacement for
recording the complete decision and sample count in an artifact.

## Bootstrap

`bootstrap_interval` uses deterministic percentile resampling. Callers provide
the seed, number of resamples, confidence level, and interval mode so a report
can be reproduced byte-for-byte. `compare_paired_with_bootstrap` applies the
same interval to paired deltas.

This implementation is intentionally not BCa, studentized, or hierarchical
bootstrap. Empty input, mismatched pair lengths, invalid confidence or
resample settings, and non-finite values return `BootstrapError`; callers
should surface the error instead of emitting an empty interval.

## Outliers

`filter_outliers` is a report-only transform. Tukey fences use IQR; MAD trim
uses the median absolute deviation. Preserve the raw observations and record
the selected policy, bounds, and retained count alongside any filtered plot.
Filtering must never change the runner's pass/fail result or rewrite JSONL.
