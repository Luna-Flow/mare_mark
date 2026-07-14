# 验证

先运行窄检查，再扩大到完整矩阵：

```sh
moon test src/report
moon test src/cli --target native
moon check --target js
moon check --target native
moon test
moon info
moon fmt
```

报告测试覆盖结构化 JSON、XML/HTML 转义、折线与 heatmap 渲染、JSONL 到 Plot IR
转换。仓库内 JSONL fixture 还可执行 native CLI 端到端 smoke test。

这些测试只证明固定范围内的行为，不证明统计置信区间、bootstrap 校正、benchmark
期间的文件流式写入或所有 PlotKind 的完整领域语义。
