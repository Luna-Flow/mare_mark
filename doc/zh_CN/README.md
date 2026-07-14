# Mare Mark 文档

本文档描述 `0.2.0` 当前实现；公开名称与签名以各包的
`pkg.generated.mbti` 为准。

建议先阅读[快速上手](./getting_started.md)、[架构](./architecture.md)和
[验证](./verification.md)。

## 核心包指南

- Runner：[API](./runner/api.md)、[教程](./runner/tutorial.md)、[设计](./runner/design.md)
- 统计：[API](./stats/api.md)、[教程](./stats/tutorial.md)、[设计](./stats/design.md)
- 报告：[API](./report/api.md)、[教程](./report/tutorial.md)、[设计](./report/design.md)

## 其他包

`model`、`generator`、`fixture`、`event`、`ir_sink`、`experiment`、
`ir_model`、`tune`、`tune_gemm` 和 `cli` 的职责已汇总在架构文档中；后续包级
文档仍需与其真实实现和生成接口同步扩展。

## 稳定性

Mare Mark 尚未到 1.0。`mmk-plot-v2` 和 JSONL 字段是带版本的 artifact，
但本版本不承诺所有包类型长期兼容。各设计页会明确列出当前限制。
