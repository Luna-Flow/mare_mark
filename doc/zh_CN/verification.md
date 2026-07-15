# 验证

先运行窄检查，再扩大到完整矩阵：

```sh
moon test src/report
moon test src/cli --target native
moon test --target js
moon test --target native
moon check --target js
moon check --target native
moon test
moon coverage analyze
moon info
moon fmt
```

报告测试覆盖结构化 JSON、XML/HTML 转义、折线与 heatmap 渲染、JSONL 到 Plot IR
转换。仓库内 JSONL fixture 还支持 native report 与 replay dry-run 端到端 smoke test。
事件测试验证 `mmka_1` 标记、sink fan-out，以及可重放的最小化失败。

统计测试验证确定性 percentile bootstrap 区间与非法配置处理，但不证明 BCa 校正、
层次重采样、benchmark 期间的文件流式写入或所有 PlotKind 的完整领域语义。CI 将
未覆盖可执行行上限设为 360，以防止覆盖静默退化；该预算不是覆盖率百分比，也不能
替代基于风险的测试。
