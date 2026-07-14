# `stats` 设计

统计是显式数组上的纯变换。原始事件由 sink 保存，因此过滤不会改写历史 observation。

`compare_paired` 当前使用配对差中位数与 practical percentage threshold。其
`Interval` 保存差值的四分位范围，不是 bootstrap 或 confidence interval。空输入返回
中性 summary 与 `Unknown`，不会抛错。

