# `report` チュートリアル

```sh
moon run src/cli --target native -- report input.jsonl output.html
```

Observation event には `implementation`、`dataset_id`、`elapsed_us` が必要で、
summary event が `run_id` を提供します。default scaling projection は calibration と
validation event を無視します。

Plot IR を直接使う場合は `PlotPoint`、`Plot`、`PlotDocument` を作り、`plot_json`、
`plot_svg`、`html` を呼びます。renderer が output context ごとに escape します。

