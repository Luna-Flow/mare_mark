# `stats` 设计

统计是显式数组上的纯变换。原始事件由 sink 保存，因此过滤不会改写历史 observation。

`compare_paired` 当前使用配对差中位数与 practical percentage threshold。其
默认 `Interval` 为保持兼容继续保存差值的四分位范围。
`compare_paired_with_bootstrap` 对配对差进行有放回重采样，并返回由显式 seed、
重采样数和置信水平决定的 percentile interval。

非法 bootstrap 输入通过 `BootstrapError` 表示。当前实现不是 BCa、studentized 或
hierarchical bootstrap。`summarize` 的空输入仍返回中性 summary，bootstrap 空样本则会被拒绝。
