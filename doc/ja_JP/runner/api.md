# `runner` API

- `Implementation::in_process`: stateful callback、`Implementation::worker`: native isolated subprocess を登録します。どちらも async backend 用の blocking `synchronize` hook を設定できます。
- `WorkerSpec::new`: argument encode、output decode、timeout、working directory を定義します。
- `OutputSink::new`: output を fold し、`Bench::keep` で値を保持します。
- `single_step`: immutable な common-case description を作り、combinator は新しい値を返し、`compile` は configuration error を集約します。
- `ValidatedBenchPlan` と `ValidatedProtocol`: runtime boundary が受け取る唯一の configuration type です。
- `ProtocolPreset`: `QuickCheck`、`Development`、`RegressionGate`、validated custom protocol を提供します。
- `RunContext`: protocol、environment、observation sink、seed をまとめます。
- `balanced_order`: block id ごとに実行順を回転します。
- `run(plan, context)`: fingerprint、計時外 validation/shrink、balanced measurement、event 発行、reset を行い `RunSummary` を返します。

`run` は implementation ごとに target batch time へ calibration し、iteration と
sample-time の上限を適用します。`SharedBatchSize` の場合だけ共通 batch size を使い、
exploratory と confirmatory observation は別 phase として保存します。

JSONL summary は device、thread/concurrency count、frequency policy を含む完全な
`EnvironmentSnapshot` を記録します。繰り返した valid observation は `stats.summarize`
で median に集約できます。

正確な generic signature は `src/runner/pkg.generated.mbti` を参照してください。
