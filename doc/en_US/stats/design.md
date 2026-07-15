# `stats` Design

Statistics are pure transformations over explicit arrays. Raw event storage is
owned by sinks, so filtering cannot rewrite historical observations.

`compare_paired` currently uses median paired delta and a practical percentage
threshold. Its default `Interval` continues to store delta quartiles for
backward-compatible descriptive analysis. `compare_paired_with_bootstrap`
resamples paired deltas with replacement and reports a deterministic percentile
interval; callers must provide the seed, resample count, and confidence level.

Invalid bootstrap input is represented by `BootstrapError`. The implementation
is a percentile bootstrap, not bias-corrected accelerated (BCa), studentized, or
hierarchical bootstrap. Empty inputs to `summarize` remain neutral, while empty
bootstrap samples are rejected.
