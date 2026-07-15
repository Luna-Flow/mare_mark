# `stats` API

- `summarize` 返回 count、极值、mean、median、MAD、quartile、IQR 和总体标准差。
- `paired_deltas` 计算 candidate 减 baseline 的配对差。
- `compare_paired` 返回相对中位差、speedup、四分位区间、decision 和有效样本数。
- `bootstrap_interval` 使用显式 seed、重采样数、置信水平和 interval mode，返回确定性的 percentile bootstrap 区间。
- `compare_paired_with_bootstrap` 将该区间应用到配对 baseline/candidate 测量。
- `filter_outliers` 应用只报告、Tukey fence 或 MAD trim 策略。
- `is_faster` 判断 `Faster` decision。

Bootstrap 函数返回 `Result`；`BootstrapError` 区分空样本、配对长度不一致、非法配置和非有限值。

精确签名见 `src/stats/pkg.generated.mbti`。
