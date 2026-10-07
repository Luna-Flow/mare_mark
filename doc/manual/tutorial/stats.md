# `stats` Tutorial

```moonbit nocheck
let comparison = @stats.compare_paired(
  "baseline",
  "candidate",
  [100.0, 101.0, 99.0],
  [92.0, 91.0, 93.0],
  5.0,
  @model.confirmatory_interval(),
)
let candidate_is_faster = @stats.is_faster(comparison)

let bootstrap = @stats.compare_paired_with_bootstrap(
  "baseline",
  "candidate",
  [100.0, 101.0, 99.0],
  [92.0, 91.0, 93.0],
  5.0,
  @model.confirmatory_interval(),
  42UL,
  2000,
  95.0,
).unwrap()
```

Keep baseline and candidate arrays in the same block/repetition order. Apply an
outlier policy to a derived analysis view; do not erase raw observations.
Record the bootstrap seed and resample count with the experiment configuration.
