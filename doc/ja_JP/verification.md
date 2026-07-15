# 検証

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

レポートテストは structured JSON、XML/HTML escape、line/heatmap rendering、
JSONL から Plot IR への変換を確認します。同梱 fixture で native report と replay
dry-run の end-to-end smoke test も実行できます。event test は `mmka_1` marker、
sink fan-out、replay 可能な最小化 failure を検証します。

stats test は決定的な percentile bootstrap interval と不正設定の処理を検証しますが、
BCa correction、hierarchical resampling、benchmark 中の filesystem streaming、全
PlotKind の domain semantics は保証しません。CI は未カバーの実行可能行を 360 以下に
制限しますが、この budget は percentage でも risk-based test の代替でもありません。
