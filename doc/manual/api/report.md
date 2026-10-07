# `report` API

`report` projects Plot IR and JSONL events into portable artifacts.

- `document_from_jsonl` parses observations, validations, failure artifacts, and summaries into plot and differential IR.
- Plot projection excludes invalid or infrastructure-failed `(case, implementation, dataset)` keys, invalid observations, and discarded batches.
- `plot_json` emits valid escaped `mmks_1` JSON.
- `plot_svg` emits accessible SVG with dynamic scales, axes, labels, legends, tooltips, and series colors.
- `html` emits a report with mismatch rows, flags diffs, capability coverage, corpus denominators, minimal counterexamples, inline CSS, and SVG.

Scaling, interval, and change-point plots connect per-series category averages.
Raw distribution, block order, outlier, and Pareto plots use points. Heatmap
plots use colored cells. Exact signatures are in `src/report/pkg.generated.mbti`.

## Projection boundary

`document_from_jsonl` is a pure projection from the event stream to
`ir_model.PlotDocument`. It does not read files, inspect the host, rerun a
worker, or recompute a validation oracle. The CLI owns stdin/filesystem paths;
library callers can provide a JSONL string directly.

The projection keeps protocol metadata, environment and capability coverage,
corpus denominators, flags, validation mismatches, and minimal counterexamples.
It drops only observations that cannot support a valid plot: invalid outcomes,
infrastructure failures, and discarded batches. A rejected candidate remains
visible in the differential section so the report cannot imply “faster and
correct” from timing rows alone.

## Artifact choices

| Function | Output | Use |
| --- | --- | --- |
| `plot_json` | escaped `mmks_1` JSON | interchange, snapshots, downstream tools |
| `plot_svg` | accessible SVG | embedding in docs or review comments |
| `html` | self-contained HTML | sharing without a server or network |

`plot_svg` derives scales, axes, labels, legends, tooltips, and series colors
from IR. It does not embed external fonts or scripts. `html` inlines CSS and
SVG, then adds mismatch rows, flags diffs, capability tables, corpus
denominators, and counterexample details.

## Minimal conversion

```moonbit nocheck
let document = @report.document_from_jsonl(events_jsonl, target="native").unwrap()
let json = @report.plot_json(document)
let plot = @ir_model.Plot::new(
  @ir_model.PlotKind::Scaling,
  "latency",
  "us",
  "none",
  [],
)
let svg = @report.plot_svg(plot)
let page = @report.html(document)
```

Keep the original JSONL next to generated artifacts. JSON/SVG/HTML are views;
the event stream is the audit record used to explain missing points and failed
validation.
