# `runner` API

`runner` 管理可执行 benchmark case 和单调时钟 batch。

- `Implementation::in_process` 注册带状态回传的进程内实现；`Implementation::worker` 注册 native 隔离子进程。
- `WorkerSpec::new` 定义参数编码、输出解码、timeout 与工作目录。
- `OutputSink::new` 折叠输出，并通过 `Bench::keep` 保留最终值。
- `DifferentialCase::new` 组合 fixture、实现、oracle、证据编码、shrinker、replay、scale 与 output sink。
- `balanced_order` 按 block id 轮转实现顺序。
- `run_case` 先 fingerprint 并在计时外逐步验证/缩减失败，再执行 balanced measurement、写事件并返回 `RunSummary`。

`run_case` 会为每个实现向目标 batch 时间校准，并受 iteration 与 sample-time 上限
约束；只有选择 `SharedBatchSize` 时才应用共同 batch size。exploratory 与
confirmatory observation 使用不同 phase。

精确泛型签名见 `src/runner/pkg.generated.mbti`。
