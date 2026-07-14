# `report` Tutorial

## From JSONL

```sh
moon run src/cli --target native -- report input.jsonl output.html
```

Observation events require `implementation`, `dataset_id`, and `elapsed_us`.
A summary event supplies `run_id`. Calibration and validation events are safely
ignored by the default scaling projection.

## From Plot IR

Construct `PlotPoint`, `Plot`, and `PlotDocument`, then call `plot_json`,
`plot_svg`, or `html`. Keep plot titles, units, series names, and category labels
as unescaped domain text; the renderer escapes output contexts.

