# ir_model tutorial

This tutorial builds report documents directly in Plot IR, so you can publish
results that do not come from a JSONL stream, such as a tuning sweep or a
summary computed with `stats`.

| I want to | Use |
| --- | --- |
| build a report document by hand | `@ir_model.PlotDocument::new` |
| plot one value per scale and series | `@ir_model.Plot::new` with `PlotPoint::new` |
| choose how a plot is drawn | `@ir_model.PlotKind` |
| attach mismatches and counterexamples | `@ir_model.DifferentialReport::new` |
| render the document | `@report.html`, `@report.plot_json`, `@report.plot_svg` |

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/ir_model",
  "Luna-Flow/mare_mark/report",
  "Luna-Flow/mare_mark/stats",
}
```

```moonbit
test "a document by hand" {
  let points = [
    @ir_model.PlotPoint::new("64", 0.8, "scalar"),
    @ir_model.PlotPoint::new("128", 3.1, "scalar"),
    @ir_model.PlotPoint::new("64", 0.5, "blocked"),
    @ir_model.PlotPoint::new("128", 1.4, "blocked"),
  ]
  let plot = @ir_model.Plot::new(@ir_model.PlotKind::Scaling, "GEMM time", "ms/op", "median", points)
  let document = @ir_model.PlotDocument::new("sweep-1", "native", [plot])
  inspect(@report.html(document).contains("GEMM time"), content="true")
}
```

## Everyday tasks

### Plot comparison results

Turn `stats` comparisons into an interval plot, one point per dataset:

```moonbit
test "interval plot from comparisons" {
  let baseline = [[100.0, 101.0, 99.0], [400.0, 404.0, 398.0]]
  let candidate = [[90.0, 92.0, 91.0], [410.0, 409.0, 412.0]]
  let points = []
  for dataset in 0..<2 {
    let result = @stats.compare_paired(
      "baseline", "candidate", baseline[dataset], candidate[dataset], 2.0, @model.confirmatory_interval(),
    )
    points.push(@ir_model.PlotPoint::new(dataset.to_string(), result.relative_delta_pct, "candidate"))
  }
  let plot = @ir_model.Plot::new(@ir_model.PlotKind::Interval, "Relative median delta", "%", "point estimate", points)
  inspect(plot.points[0].y, content="-9")
  inspect(plot.points[1].y, content="2.5")
}
```

### Attach correctness evidence

```moonbit
test "differential evidence" {
  let corpus = @ir_model.CorpusSummary::new(200, 197, 2, 1, 0)
  let report = @ir_model.DifferentialReport::new([], [@ir_model.CapabilityCell::new("fast", "unsupported", 1)], [], corpus)
  let document = @ir_model.PlotDocument::new("corpus-run", "native", [], differential=report)
  inspect(@report.html(document).contains("failed 2"), content="true")
}
```

## Going further

Render with `@report.plot_svg` to embed one chart in your own page, or export
with `@report.plot_json` for other tools; see the [report API](../api/report.md).

## Common pitfalls

- **Numeric x values.** They are strings and are spaced evenly in order of
  first appearance; sort the points if order matters.
- **Empty series names.** They are drawn as `value`.

## Next steps

- [ir_model API](../api/ir_model.md), [ir_model design](../design/ir_model.md).
- [report tutorial](report.md).
