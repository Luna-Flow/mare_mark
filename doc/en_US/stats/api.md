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
