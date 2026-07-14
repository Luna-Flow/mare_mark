# `stats` チュートリアル

```moonbit nocheck
let comparison = @stats.compare_paired(
  "baseline", "candidate",
  [100.0, 101.0, 99.0], [92.0, 91.0, 93.0],
  5.0, @model.confirmatory_interval(),
)
let candidate_is_faster = @stats.is_faster(comparison)
```

baseline と candidate の配列は同じ block/repetition 順序を保ちます。outlier policy
は派生ビューに適用し、raw observation は削除しません。

