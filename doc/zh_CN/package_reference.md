# 包参考

本文按职责解释 `0.3.0` 的公开包边界。精确泛型签名以各目录的
`pkg.generated.mbti` 为准；本文重点说明“该由哪个包决定、哪些工作会进入计时区间、
哪些结果必须保留为证据”。

## `model`

`model` 是共享协议词汇，包含数据集/测量键、运行协议、环境快照、执行结果、观察值、
校验失败、重放信息和版本标记。`mmkp_1` 标识协议、`mmka_1` 标识可重放产物、
`mmks_1` 标识 Plot/JSON schema。

不要用字符串或数值零混合失败：`ExecutionOutcome` 会区分正常值、附带 flags 的值、
不支持、解析失败、trap、进程退出、超时和预期差异。状态型操作使用
`OperationResult` 同时返回 outcome 与下一步 context。

## `generator`

`generator` 负责确定性输入。`derive_seed` 和 `measurement_seed` 把 suite、case、
dataset、repetition、block 隔离开；`GenerationContext` 记录生成器 id/version；
`stable_fingerprint` 用于来源追踪，不是密码学哈希。

## `fixture`

`fixture` 管理 generated input 到 prepared input 的生命周期。不可变输入优先使用
`Fixture::immutable`；需要 clone、prepare、reset 或 workspace 时使用
`Fixture::new`。`SetupPolicy` 明确 setup 的频率、是否纳入测量以及 workspace scope。
“每次操作新分配”和“复用 workspace”是两个不同实验，不能只改实现而不改协议说明。

## `experiment`

`ReferenceOracle` 计算期望序列，`RelationalOracle` 比较两个实现，二者可以组合。
`Shrinker` 在保持失败谓词成立时缩小输入，并返回 shrink path；这个路径应写入失败产物，
让用户知道最小反例是怎样得到的。`crossover_from_labels` 会显式返回非单调和证据不足，
不能把它们伪装成可部署阈值。

## `runner`

`runner` 是唯一拥有测量循环的包。先构造 `BenchSpec`，再 `compile` 为
`ValidatedBenchPlan`，最后用 `RunContext` 调用 `run`。

运行顺序为：

```text
materialize -> oracle 校验 -> prepare -> 计时外校准
           -> balanced timed block -> fold output -> reset -> emit event
```

`Implementation::stateless` 用于无状态 payload；`in_process` 带 context；`worker`
使用原生子进程并保存 timeout、exit code、stdout 和 stderr。异步设备通过
`synchronize` 把排队工作约束在计时边界内。exploratory 与 confirmatory 观察值分开记录，
统计时不要混成一个样本集。

## `event` 与 `ir_sink`

`InMemorySink` 适合测试和本地分析，`JsonlSink` 保存完整 JSONL，
`streaming_jsonl` 逐行输出，`tee` 同时写入两个 sink。JSONL 应视为 append-only 审计流；
outlier 策略只能作用于派生视图，不能改写原始观察值。

## `stats`

`summarize` 返回极值、均值、中位数、MAD、四分位数、IQR 和总体标准差。
`compare_paired` 使用配对中位差和 practical threshold；bootstrap 版本要求显式 seed、
resample 数、置信度与 interval mode。当前是 percentile bootstrap，不是 BCa、
studentized 或 hierarchical bootstrap。

baseline 与 candidate 的第 i 个值必须来自相同 dataset/repetition/block。空样本、长度不等、
非法置信度和非有限值会返回 `BootstrapError`，而不是一个看似合理的区间。

## `ir_model` 与 `report`

`ir_model` 定义 `PlotDocument`、多种 `PlotKind` 和 differential report。
`report.document_from_jsonl` 把事件转换为 IR；`plot_json` 输出 `mmks_1`；
`plot_svg` 渲染单图；`html` 生成包含 mismatch、flags、capability、corpus 和最小反例的
自包含页面。所有 report 函数都不访问文件系统，文件 IO 只属于 `cli`。

无效观察值、discarded batch 和 infrastructure failure 不进入性能曲线；校验失败仍保留在
differential 区域，避免“更快但错误”的实现被报告成 speedup。

## `tune`

`CandidateSpace` 描述候选枚举、id、有效性与邻居；`TuningBudget` 分离 exploration、
confirmation 和 holdout；`pareto_frontier` 保留非支配候选；`seeded_order` 保证评估顺序可复现。
该包只提供策略和纯数据模型，应用仍负责 build、运行、正确性校验和事件记录。

## `tune_gemm`

`GemmScale` 记录形状、batch/reuse 和布局；`GemmCandidate` 记录 blocking、microkernel、
loop order、packing、allocation mode 与 timing scope。安全流程是：生成可复现矩阵、过滤无效
candidate、用 reference 校验、只测约定 timing scope、在 holdout shape 上确认、最后序列化完整配置。

## `cli`

```sh
mare-mark report events.jsonl report.html
mare-mark report - -
mare-mark replay failure.jsonl --dry-run
mare-mark replay failure.jsonl --yes
```

`report` 支持 stdin/stdout。`replay` 是原生外部进程副作用：先用 `--dry-run` 检查，真正执行还需
显式 `--yes`。不要执行来源不可信的重放产物。

## 稳定性

生成接口是名称和签名的权威来源。benchmark 阈值、私有存储、HTML/CSS 细节、内部算法选择和
未承诺的候选枚举顺序都不是长期兼容保证。
