# `report` API

- `document_from_jsonl` 把 observation、validation、failure artifact 与 summary 解析为 plot/differential IR。
- `plot_json` 输出已正确转义的 `mmk-plot-v2` JSON。
- `plot_svg` 输出带动态尺度、坐标轴、标签、图例、tooltip 和系列颜色的可访问 SVG。
- `html` 输出 mismatch、flags diff、能力覆盖、corpus 分母、最小反例及内嵌 CSS/SVG。

Scaling、interval、change-point 连接各系列的类别均值；raw distribution、block
order、outlier、Pareto 使用点；heatmap 使用色块。精确签名见
`src/report/pkg.generated.mbti`。
