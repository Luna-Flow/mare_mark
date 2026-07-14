# `runner` 教程

1. 用 materialize、fingerprint、clone、prepare、reset callback 创建 `Fixture`。
2. 注册至少一个 `Implementation`。
3. 定义可阻止结果被优化掉的 `OutputSink`。
4. 用有序 scale 创建 `DifferentialCase`。
5. 把 `RunProtocol`、`EnvironmentSnapshot`、`ObservationSink` 交给 `run_case`。
6. 先保留原始 observation，再计算 summary。

JS 与 native 必须使用独立 run；两者的 elapsed 值不是同一可比较总体。

