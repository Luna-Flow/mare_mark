# `runner` チュートリアル

1. materialize、fingerprint、clone、prepare、reset callback を持つ `Fixture` を作ります。
2. 一つ以上の `Implementation` を登録します。
3. 結果消去を防ぐ `OutputSink` を定義します。
4. ordered scale を持つ `DifferentialCase` を作ります。
5. `RunProtocol`、`EnvironmentSnapshot`、`ObservationSink` を `run_case` に渡します。
6. summary の前に raw observation を保存します。

JS と native は別 run とし、elapsed value を同じ母集団として比較しません。

