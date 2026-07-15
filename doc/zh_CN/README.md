# mare_mark 文档

本文档描述 `0.3.0` 当前实现；公开名称与签名以各包的
`pkg.generated.mbti` 为准。

建议先阅读[快速上手](./getting_started.md)、[架构](./architecture.md)、
[包参考](./package_reference.md)和[验证](./verification.md)。

## 核心包指南

- Runner：[API](./runner/api.md)、[教程](./runner/tutorial.md)、[设计](./runner/design.md)
- 统计：[API](./stats/api.md)、[教程](./stats/tutorial.md)、[设计](./stats/design.md)
- 报告：[API](./report/api.md)、[教程](./report/tutorial.md)、[设计](./report/design.md)

## 包职责地图

| 边界 | 包 |
| --- | --- |
| 协议与事件 | `model`、`event`、`ir_sink` |
| 输入与生命周期 | `generator`、`fixture` |
| 校验与测量 | `experiment`、`runner` |
| 分析与呈现 | `stats`、`ir_model`、`report` |
| 搜索策略 | `tune`、`tune_gemm` |
| 原生文件/进程副作用 | `cli` |

## 其他包

所有包的职责、测量边界和稳定性说明见[包参考](./package_reference.md)。
精确的公开名称与签名仍以各包的 `pkg.generated.mbti` 为准。

## 稳定性

mare_mark 尚未到 1.0。Plot schema `mmks_1` 与 JSONL artifact version `mmka_1`
是显式兼容标记，
但本版本不承诺所有包类型长期兼容。各设计页会明确列出当前限制。
