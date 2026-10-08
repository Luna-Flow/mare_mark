# ir_model API

## Purpose

`Luna-Flow/mare_mark/ir_model` defines Plot IR, the portable document that
`report` builds from events and renders as JSON, SVG or HTML: plots of
categorical points and a differential report of mismatches, capabilities,
counterexamples and corpus counts. See the [ir_model design](../design/ir_model.md).

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
}
pub fn PlotDocument::new(String, String, Array[Plot], differential? : DifferentialReport) -> Self
```

`new(run_id, target, plots)` sets `schema_version` to `SchemaVersion::V1`
(`mmks_1`); `differential` defaults to `DifferentialReport::empty()`.

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
}
pub fn Plot::new(PlotKind, String, String, String, Array[PlotPoint]) -> Self
```

`unit` labels the y axis; `interval_kind` describes what the values are
(`"raw"`, `"median"`, a confidence level).

### `PlotPoint`

`PlotPoint` is one value at a categorical x position in a named series.

```mbti
pub struct PlotPoint {
  x : String
  y : Double
  series : String
}
pub fn PlotPoint::new(String, Double, String) -> Self
```

An empty `series` is drawn as `"value"`.

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
  inspect(document.schema_version.identifier(), content="mmks_1")
  inspect(document.differential.corpus.total, content="0")
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
