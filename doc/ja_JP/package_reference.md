# Package Reference

このページは `0.3.0` の package 責務、測定境界、安定性を説明します。
正確な generic signature は各 `pkg.generated.mbti` を基準にします。

## `model`

`model` は dataset/measurement key、run protocol、environment、execution
outcome、observation、validation failure、replay spec、version marker を共有する
語彙です。`mmkp_1`、`mmka_1`、`mmks_1` はそれぞれ protocol、artifact、Plot schema
を識別します。失敗を数値ゼロに変換せず、`ExecutionOutcome` の分類を保持します。

## `generator` と `fixture`

`generator` は suite、case、dataset、repetition、block ごとに seed を分離し、
再現可能な入力を作ります。fingerprint は provenance 用であり暗号学的 hash ではありません。

`fixture` は materialize、clone、prepare、reset と setup policy を所有します。
allocation を毎回行う実験と workspace を再利用する実験は別の protocol として記録します。

## `experiment` と `runner`

`experiment` は reference/relational oracle、shrinker、crossover 判定を提供します。
縮小された反例には shrink path を残します。

`runner` は唯一の measurement loop です。

```text
materialize -> validate -> prepare -> calibrate outside timing
           -> balanced timed block -> fold -> reset -> emit
```

`stateless`、context 付き `in_process`、native subprocess の `worker` を選べます。
timeout、exit code、stdout、stderr は typed failure として保存します。exploratory と
confirmatory observation は別の母集団として扱います。

## `event`、`stats`、`report`

`event` は in-memory、JSONL、stream、tee sink を提供します。raw JSONL は append-only
の audit record であり、outlier policy で書き換えません。

`stats` は summary、paired median delta、deterministic percentile bootstrap を提供します。
paired array の同じ index は同じ dataset/repetition/block でなければなりません。
現在の bootstrap は BCa、studentized、hierarchical resampling ではありません。

`report` は JSONL を `ir_model.PlotDocument` に変換し、JSON/SVG/HTML を純粋に生成します。
invalid observation と discarded batch は plot から除外し、validation failure は
differential section に残します。filesystem effect は `cli` の責務です。

## `tune` と `tune_gemm`

`tune` は candidate space、budget、holdout、score、Pareto frontier をモデル化します。
build、実行、正しさの検証、environment capture は application が明示的に行います。

`tune_gemm` は shape、layout、packing、workspace、microkernel、timing scope を持つ具体例です。
reference で候補を検証してから測定し、holdout shape を confirmation に使用します。

## `cli`

```sh
mare-mark report events.jsonl report.html
mare-mark replay failure.jsonl --dry-run
mare-mark replay failure.jsonl --yes
```

replay は native の外部 process effect です。信頼できる artifact だけを dry-run で確認し、
実行時は `--yes` を明示します。

## Stability

公開名と signature は生成 interface が authoritative です。benchmark threshold、private
storage、renderer styling、内部 algorithm は compatibility promise ではありません。
