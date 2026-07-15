# `report` API

- `document_from_jsonl`: observation、validation、failure artifact、summary を plot/differential IR に変換します。
- plot projection は invalid/infrastructure failure の `(case, implementation, dataset)`、invalid observation、discarded batch を除外します。
- `plot_json`: escape 済み `mmks_1` JSON を生成します。
- `plot_svg`: dynamic scale、axis、label、legend、tooltip、series color を持つ SVG。
- `html`: mismatch、flags diff、capability coverage、corpus denominator、minimal counterexample、inline CSS/SVG を含む report。

Scaling、interval、change-point は series average を線で結びます。raw distribution、
block order、outlier、Pareto は point、heatmap は cell を使います。正確な signature は
`src/report/pkg.generated.mbti` を参照してください。
