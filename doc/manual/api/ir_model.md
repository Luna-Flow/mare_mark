# ir_model API

## Purpose

`Luna-Flow/mare_mark/ir_model` defines Plot IR, the portable document that
`report` builds from events and renders as JSON, SVG or HTML: plots of
points on a categorical or linear x axis, a differential report of mismatches,
capabilities, counterexamples and corpus counts, and the paired comparisons of
implementations against a baseline. See the [ir_model design](../design/ir_model.md).

Source: [`src/ir_model/ir_model.mbt`](../../../src/ir_model/ir_model.mbt).

## Importing

Add the package to the `moon.pkg` of the package that uses it:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/ir_model",
}
```

The examples on this page call it through its default alias `@ir_model`.

## Documents

### `PlotDocument`

`PlotDocument` is one report.

```mbti
pub struct PlotDocument {
  schema_version : @model.SchemaVersion
  run_id : String
  target : String
  plots : Array[Plot]
  differential : DifferentialReport
  comparisons : ComparisonReport
}
pub fn PlotDocument::new(String, String, Array[Plot], differential? : DifferentialReport, comparisons? : ComparisonReport) -> Self
```

`new(run_id, target, plots)` sets `schema_version` to `SchemaVersion::V2`
(`mmks_2`); `differential` defaults to `DifferentialReport::empty()` and `comparisons` to `ComparisonReport::empty()`. V1 is
deprecated because it cannot identify the y-axis scale.

## Plots

### `Plot`

`Plot` is one chart.

```mbti
pub struct Plot {
  kind : PlotKind
  title : String
  unit : String
  interval_kind : String
  points : Array[PlotPoint]
  x_axis : AxisScale
  y_axis : AxisScale
  x_label : String
  note : String
}
pub fn Plot::new(PlotKind, String, String, String, Array[PlotPoint], x_axis? : AxisScale, y_axis? : AxisScale, x_label? : String, note? : String) -> Self
```

The positional arguments are `kind`, `title`, `unit`, `interval_kind` and
`points`. `unit` labels the y axis; `interval_kind` describes what the values
are (`"raw"`, `"median"`, a confidence level). `x_axis` (default
`Categorical`) places the x values, `x_label` (default `""`) names the x axis
under the plot, and `note` (default `""`) is a sentence that explains the
plot; the HTML shows it in the figure caption and the SVG in its
description.

### `AxisScale`

`AxisScale` says how the x values of a plot are placed.

```mbti
pub(all) enum AxisScale {
  Categorical
  Linear
  Log
}
```

| Value | Placement |
| --- | --- |
| `Categorical` | evenly spaced, in order of first appearance; ticks show the x text |
| `Linear` | sorted by numeric value and spaced in proportion to it; every x must parse as a finite number |
| `Log` | placed by log10 of positive finite values |

A renderer falls back to `Categorical` when an x value of a `Linear` plot is
not a finite number; `report.plot_svg` does, and it draws heatmaps
categorically in any case.

`AxisScale` is `Categorical`, `Linear` or `Log`; x defaults to
`Categorical`, y to `Linear`. A log axis places positive values by
`log10(value)`, so callers should select it only for positive finite values.

### `PlotPoint`

`PlotPoint` is one value at an x position in a named series.

```mbti
pub struct PlotPoint {
  x : String
  y : Double
  series : String
}
pub fn PlotPoint::new(String, Double, String) -> Self
```

`x` is text, also on a linear axis (for example `"1024"`). An empty
`series` is drawn as `"value"`.

### `PlotKind`

`PlotKind` selects how a plot is drawn and labelled.

```mbti
pub(all) enum PlotKind {
  Scaling
  RawDistribution
  BlockOrder
  Interval
  Outlier
  ChangePoint
  Heatmap
  Pareto
}
```

`Scaling`, `Interval` and `ChangePoint` are drawn as points with lines through
per-category means; `Heatmap` as cells; the others as points.

```moonbit
test "a plot document" {
  let plot = @ir_model.Plot::new(
    @ir_model.PlotKind::Interval,
    "Median delta",
    "µs",
    "95% bootstrap",
    [@ir_model.PlotPoint::new("1024", -9.5, "candidate")],
  )
  let document = @ir_model.PlotDocument::new("run-7", "native", [plot])
  inspect(document.schema_version.identifier(), content="mmks_2")
  inspect(document.differential.corpus.total, content="0")
  inspect(document.plots[0].x_axis is Categorical, content="true")
  inspect(document.comparisons.rows.length(), content="0")
}

test "a plot on a linear axis" {
  let points = [
    @ir_model.PlotPoint::new("1024", 10.1, "scalar"),
    @ir_model.PlotPoint::new("4096", 40.6, "scalar"),
  ]
  let plot = @ir_model.Plot::new(
    @ir_model.PlotKind::Scaling,
    "vector-add",
    "µs/op",
    "median",
    points,
    x_axis=Linear,
    x_label="scale",
    note="Median of the confirmatory observations.",
  )
  inspect(plot.x_label, content="scale")
}
```

## Differential report

### `DifferentialReport`

`DifferentialReport` gathers the correctness evidence of a run.

```mbti
pub struct DifferentialReport {
  mismatches : Array[MismatchRow]
  capabilities : Array[CapabilityCell]
  counterexamples : Array[Counterexample]
  corpus : CorpusSummary
}
pub fn DifferentialReport::new(Array[MismatchRow], Array[CapabilityCell], Array[Counterexample], CorpusSummary) -> Self
pub fn DifferentialReport::empty() -> Self
```

`empty()` has no rows and all corpus counts `0`.

### `MismatchRow`

`MismatchRow` is one failed validation.

```mbti
pub struct MismatchRow {
  implementation : String
  operation : String
  operands : Array[String]
  expected : String
  actual : String
  flags_diff : String
  trap : String
  fingerprint : String
  replay_command : String
}
pub fn MismatchRow::new(String, String, Array[String], String, String, String, String, String, String) -> Self
```

`report` fills `flags_diff` as the expected flags, `" → "`, and the actual
flags, each joined with `", "`.

### `CapabilityCell`

`CapabilityCell` counts the outcomes of one kind for one implementation.

```mbti
pub struct CapabilityCell {
  implementation : String
  outcome_kind : String
  count : Int
}
pub fn CapabilityCell::new(String, String, Int) -> Self
```

`outcome_kind` is an `ExecutionOutcome::kind` string.

### `Counterexample`

`Counterexample` is a minimized failing input.

```mbti
pub struct Counterexample {
  implementation : String
  minimal_input : String
  fingerprint : String
  shrink_path : Array[String]
  replay_command : String
}
pub fn Counterexample::new(String, String, String, Array[String], String) -> Self
```

### `CorpusSummary`

`CorpusSummary` counts validation outcomes.

```mbti
pub struct CorpusSummary {
  total : Int
  passed : Int
  failed : Int
  unsupported : Int
  expected_difference : Int
}
pub fn CorpusSummary::new(Int, Int, Int, Int, Int) -> Self
```

```moonbit
test "a differential report" {
  let row = @ir_model.MismatchRow::new("fast", "add", ["0.1", "0.2"], "0.3", "0.30000000000000004", " → inexact", "", "sha256:…", "worker fast 3")
  let report = @ir_model.DifferentialReport::new([row], [], [], @ir_model.CorpusSummary::new(10, 9, 1, 0, 0))
  let document = @ir_model.PlotDocument::new("run-8", "js", [], differential=report)
  inspect(document.differential.mismatches[0].operation, content="add")
}
```

## Comparisons

### `ComparisonReport`

`ComparisonReport` holds the paired comparisons of a document and the
settings they were made with.

```mbti
pub struct ComparisonReport {
  rows : Array[ComparisonRow]
  practical_delta_pct : Double
  outlier_policy : String
  confidence_pct : Double
  resamples : Int
  min_blocks : Int
  run_seed : UInt64
  protocol_recorded : Bool
  seed_recorded : Bool
  note : String
}
pub fn ComparisonReport::new(Array[ComparisonRow], Double, String, Double, Int, Int, UInt64, Bool, Bool, String) -> Self
pub fn ComparisonReport::empty() -> Self
```

| Field | Meaning |
| --- | --- |
| `rows` | one row per candidate, scale and case |
| `practical_delta_pct` | the decision threshold, in percent |
| `outlier_policy` | the `OutlierPolicy::text()` of the filter applied to the paired deltas |
| `confidence_pct`, `resamples` | the bootstrap interval's confidence and number of resamples |
| `min_blocks` | the fewest usable blocks for which a row is decided |
| `run_seed` | the seed the row seeds are derived from |
| `protocol_recorded`, `seed_recorded` | whether the threshold and policy, and the run seed, come from the record rather than from defaults |
| `note` | one human-readable sentence stating the settings and their sources |

`new` takes the fields in this order. `empty()` has no rows, zero numbers,
`false` flags and empty strings; renderers show no comparison section for it.
`report.document_from_jsonl` fills a report; the
[report API](../api/report.md#paired-comparisons) gives the rules.

### `ComparisonRow`

`ComparisonRow` is the comparison of one candidate with the baseline at one
scale of one case.

```mbti
pub struct ComparisonRow {
  case_id : String
  scale : String
  baseline : String
  candidate : String
  decision : ComparisonDecision
  reason : String
  estimate : PairedEstimate?
  interval : DeltaInterval?
  blocks_used : Int
  blocks_incomplete : Int
  blocks_outliers : Int
  seed : UInt64
}
pub fn ComparisonRow::new(String, String, String, String, ComparisonDecision, String, PairedEstimate?, DeltaInterval?, Int, Int, Int, UInt64) -> Self
```

`reason` explains an `Unknown` or `Invalid` decision and is empty otherwise.
`estimate` is `None` when no block was usable; `interval` is `None` when the
bootstrap did not run. `blocks_used` counts the complete blocks that entered
the comparison, `blocks_incomplete` the blocks without exactly one
observation of each implementation, and `blocks_outliers` the complete blocks
removed by the outlier policy. `seed` is the bootstrap seed of the row. `new`
takes the fields in this order.

### `PairedEstimate`

`PairedEstimate` holds the point estimates of a comparison, in µs/op.

```mbti
pub struct PairedEstimate {
  baseline_median_us : Double
  candidate_median_us : Double
  median_delta_us : Double
  relative_delta_pct : Double
  speedup : Double
}
pub fn PairedEstimate::new(Double, Double, Double, Double, Double) -> Self
```

Over the used blocks, with baseline times $b_i$, candidate times $c_i$ and
paired deltas $d_i = c_i - b_i$: `baseline_median_us` is
$\operatorname{med}(b)$, `candidate_median_us` is $\operatorname{med}(c)$,
`median_delta_us` is $m_d = \operatorname{med}(d)$, `relative_delta_pct` is
$100\,m_d / \operatorname{med}(b)$ and `speedup` is
$\operatorname{med}(b) / (\operatorname{med}(b) + m_d)$. The decision uses
`relative_delta_pct`, not the difference of the two medians.

### `DeltaInterval`

`DeltaInterval` is the bootstrap interval of the median paired delta.

```mbti
pub struct DeltaInterval {
  low_us : Double
  high_us : Double
  low_pct : Double
  high_pct : Double
}
pub fn DeltaInterval::new(Double, Double, Double, Double) -> Self
```

`low_us` and `high_us` are in µs/op; `low_pct` and `high_pct` are the same
bounds as a percentage of the baseline median, so they can be read next to
`relative_delta_pct` and the threshold.

### `ComparisonDecision`

`ComparisonDecision` is the outcome of a comparison.

```mbti
pub(all) enum ComparisonDecision {
  Faster
  Slower
  Equivalent
  Unknown
  Invalid
}
pub fn ComparisonDecision::text(Self) -> String
```

The values mirror `@stats.Decision`. `text` gives the lower-case name
(`"faster"`, `"slower"`, `"equivalent"`, `"unknown"`, `"invalid"`) that
`report.plot_json` writes.

```moonbit
test "a comparison row" {
  let estimate = @ir_model.PairedEstimate::new(10.0, 7.0, -3.0, -30.0, 10.0 / 7.0)
  let interval = @ir_model.DeltaInterval::new(-3.1, -2.9, -31.0, -29.0)
  let row = @ir_model.ComparisonRow::new(
    "vector-add", "1024", "scalar", "simd", Faster, "", Some(estimate), Some(interval), 8, 0, 0, 7UL,
  )
  let report = @ir_model.ComparisonReport::new([row], 2.0, "tukey_fence", 95.0, 10000, 3, 42UL, true, true, "hand-made")
  let document = @ir_model.PlotDocument::new("run-9", "native", [], comparisons=report)
  inspect(document.comparisons.rows[0].decision.text(), content="faster")
  inspect(@ir_model.ComparisonReport::empty().rows.length(), content="0")
}
```
