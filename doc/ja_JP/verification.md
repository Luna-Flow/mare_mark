# 検証

```sh
moon test src/report
moon test src/cli --target native
moon check --target js
moon check --target native
moon test
moon info
moon fmt
```

レポートテストは structured JSON、XML/HTML escape、line/heatmap rendering、
JSONL から Plot IR への変換を確認します。同梱 fixture で native CLI の smoke test
も実行できます。

この証拠は confidence interval、bootstrap correction、benchmark 中の filesystem
streaming、全 PlotKind の完全な domain semantics を保証しません。
