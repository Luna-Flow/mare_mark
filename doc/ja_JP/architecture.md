# アーキテクチャ

mare_mark は純粋な実験記述・レポート投影と、計時・ファイル IO を分離します。

| 層 | Package | 責務 |
| --- | --- | --- |
| Domain model | `model`、`ir_model`、`tune_gemm` | protocol、event、plot、tuning data |
| Pure transform | `generator`、`stats`、`experiment`、`tune`、`report` | seed、summary、decision、policy、rendering |
| Controlled runtime | `fixture`、`runner` | materialize、prepare、単調時計、reset |
| Effect adapter | `event`、`ir_sink`、`cli` | event accumulation、native file IO |

```text
GenerationContext -> Fixture -> Oracle/Worker -> ValidationFailure
                  -> balanced timed blocks -> streaming ObservationSink
                  -> JSONL -> DifferentialReport + PlotDocument -> HTML
```

payload closure はレポート生成やファイル IO を行いません。`report` は純粋な
`PlotDocument -> String`、`cli` は IO adapter です。

`run(plan, context)` は薄い effect boundary です。measurement phase の外で batch を calibration し、exploratory と
confirmatory observation を分けて生成します。tuning package は search/policy の
data model を提供し、domain 固有 microkernel の登録・実行は application が担います。
