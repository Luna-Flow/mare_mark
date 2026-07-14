# `report` 教程

```sh
moon run src/cli --target native -- report input.jsonl output.html
```

Observation event 必须含 `implementation`、`dataset_id`、`elapsed_us`，summary
event 提供 `run_id`。默认 scaling 投影会安全忽略 calibration 与 validation event。

直接使用 Plot IR 时，构造 `PlotPoint`、`Plot`、`PlotDocument`，再调用
`plot_json`、`plot_svg` 或 `html`。标题、单位、系列名和类别标签传入原始文本即可，
renderer 会按输出上下文转义。

