# `stats` API

- `summarize` 返回 count、极值、mean、median、MAD、quartile、IQR 和总体标准差。
- `paired_deltas` 计算 candidate 减 baseline 的配对差。
- `compare_paired` 返回相对中位差、speedup、四分位区间、decision 和有效样本数。
- `filter_outliers` 应用只报告、Tukey fence 或 MAD trim 策略。
- `is_faster` 判断 `Faster` decision。

精确签名见 `src/stats/pkg.generated.mbti`。

