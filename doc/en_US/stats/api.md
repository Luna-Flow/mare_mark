# `stats` API

`stats` provides descriptive summaries and practical paired decisions.

- `summarize` returns count, extrema, mean, median, MAD, quartiles, IQR, and population standard deviation.
- `paired_deltas` subtracts paired baseline values from candidate values.
- `compare_paired` returns relative median delta, speedup, an interquartile interval, decision, and valid sample count.
- `filter_outliers` applies report-only, Tukey-fence, or MAD-trim policy.
- `is_faster` recognizes the `Faster` decision.

See `src/stats/pkg.generated.mbti` for exact signatures.

