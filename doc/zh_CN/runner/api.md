# `runner` API

`runner` 管理可执行 benchmark case 和单调时钟 batch。

- `Implementation::in_process` 注册带状态回传的进程内实现；`Implementation::worker` 注册 native 隔离子进程；两者都可接收异步后端使用的阻塞式 `synchronize` 钩子。
- `WorkerSpec::new` 定义参数编码、输出解码、timeout 与工作目录。
- `OutputSink::new` 折叠输出，并通过 `Bench::keep` 保留最终值。
- `single_step` 创建不可变的常见 case 描述；组合器返回新值，`compile` 聚合配置错误。
- `ValidatedBenchPlan` 与 `ValidatedProtocol` 是运行边界接受的唯一配置类型。
- `ProtocolPreset` 提供 `QuickCheck`、`Development`、`RegressionGate` 与已验证的自定义协议。
- `RunContext` 组合 protocol、environment、observation sink 与 seed。
- `balanced_order` 按 block id 轮转实现顺序。
- `run(plan, context)` 先 fingerprint 并在计时外逐步验证/缩减失败，再执行 balanced measurement、写事件并返回 `RunSummary`。

`run` 会为每个实现向目标 batch 时间校准，并受 iteration 与 sample-time 上限
约束；只有选择 `SharedBatchSize` 时才应用共同 batch size。exploratory 与
confirmatory observation 使用不同 phase。

JSONL summary 会记录完整 `EnvironmentSnapshot`，包括 device、线程/concurrency 数与
frequency policy。对重复的有效 observation 使用 `stats.summarize` 可得到 median 汇总。

精确泛型签名见 `src/runner/pkg.generated.mbti`。
