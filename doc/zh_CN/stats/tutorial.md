# `stats` 教程

```moonbit nocheck
let comparison = @stats.compare_paired(
  "baseline", "candidate",
  [100.0, 101.0, 99.0], [92.0, 91.0, 93.0],
  5.0, @model.confirmatory_interval(),
)
let candidate_is_faster = @stats.is_faster(comparison)
```

baseline 与 candidate 数组必须保持相同 block/repetition 顺序。outlier policy 只应用
于派生分析视图，不应删除原始 observation。

