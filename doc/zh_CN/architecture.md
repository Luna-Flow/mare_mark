# 架构

Mare Mark 把纯实验描述与报告投影同计时、文件系统副作用分开。

| 层 | Package | 职责 |
| --- | --- | --- |
| 领域模型 | `model`、`ir_model`、`tune_gemm` | 协议、事件、图形和调优数据。 |
| 纯变换 | `generator`、`stats`、`experiment`、`tune`、`report` | seed、统计、决策、策略和渲染。 |
| 受控运行 | `fixture`、`runner` | materialize、prepare、单调时钟计时和 reset。 |
| 副作用适配 | `event`、`ir_sink`、`cli` | 事件累计和 native 文件 IO。 |

```text
GenerationContext -> Fixture -> Oracle/Worker -> ValidationFailure
                  -> balanced timed blocks -> streaming ObservationSink
                  -> JSONL -> DifferentialReport + PlotDocument -> HTML
```

payload 闭包不执行报告渲染或文件 IO。`report` 保持纯
`PlotDocument -> String` 边界，只有 `cli` 读写文件。

`run_case` 在 measurement phase 外校准 batch，并分别写入 exploratory 与
confirmatory observation。调优包提供搜索与策略数据模型；领域专用 microkernel
由应用负责注册和执行。
