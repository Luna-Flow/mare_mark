# `report` API

`report` projects Plot IR and JSONL events into portable artifacts.

- `document_from_jsonl` parses observations, validations, failure artifacts, and summaries into plot and differential IR.
- `plot_json` emits valid escaped `mmk-plot-v2` JSON.
- `plot_svg` emits accessible SVG with dynamic scales, axes, labels, legends, tooltips, and series colors.
- `html` emits a report with mismatch rows, flags diffs, capability coverage, corpus denominators, minimal counterexamples, inline CSS, and SVG.

Scaling, interval, and change-point plots connect per-series category averages.
Raw distribution, block order, outlier, and Pareto plots use points. Heatmap
plots use colored cells. Exact signatures are in `src/report/pkg.generated.mbti`.
