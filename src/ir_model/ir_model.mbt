///|
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

///|
pub struct PlotPoint {
  x : String
  y : Double
  series : String
}

///|
pub struct Plot {
  kind : PlotKind
  title : String
  unit : String
  interval_kind : String
  points : Array[PlotPoint]
}

///|
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

///|
pub fn MismatchRow::new(
  implementation : String,
  operation : String,
  operands : Array[String],
  expected : String,
  actual : String,
  flags_diff : String,
  trap : String,
  fingerprint : String,
  replay_command : String,
) -> MismatchRow {
  {
    implementation,
    operation,
    operands,
    expected,
    actual,
    flags_diff,
    trap,
    fingerprint,
    replay_command,
  }
}

///|
pub struct CapabilityCell {
  implementation : String
  outcome_kind : String
  count : Int
}

///|
pub fn CapabilityCell::new(
  implementation : String,
  outcome_kind : String,
  count : Int,
) -> CapabilityCell {
  { implementation, outcome_kind, count }
}

///|
pub struct Counterexample {
  implementation : String
  minimal_input : String
  fingerprint : String
  shrink_path : Array[String]
  replay_command : String
}

///|
pub fn Counterexample::new(
  implementation : String,
  minimal_input : String,
  fingerprint : String,
  shrink_path : Array[String],
  replay_command : String,
) -> Counterexample {
  { implementation, minimal_input, fingerprint, shrink_path, replay_command }
}

///|
pub struct CorpusSummary {
  total : Int
  passed : Int
  failed : Int
  unsupported : Int
  expected_difference : Int
}

///|
pub fn CorpusSummary::new(
  total : Int,
  passed : Int,
  failed : Int,
  unsupported : Int,
  expected_difference : Int,
) -> CorpusSummary {
  { total, passed, failed, unsupported, expected_difference }
}

///|
pub struct DifferentialReport {
  mismatches : Array[MismatchRow]
  capabilities : Array[CapabilityCell]
  counterexamples : Array[Counterexample]
  corpus : CorpusSummary
}

///|
pub fn DifferentialReport::new(
  mismatches : Array[MismatchRow],
  capabilities : Array[CapabilityCell],
  counterexamples : Array[Counterexample],
  corpus : CorpusSummary,
) -> DifferentialReport {
  { mismatches, capabilities, counterexamples, corpus }
}

///|
pub fn DifferentialReport::empty() -> DifferentialReport {
  DifferentialReport::new([], [], [], CorpusSummary::new(0, 0, 0, 0, 0))
}

///|
pub fn PlotPoint::new(x : String, y : Double, series : String) -> PlotPoint {
  { x, y, series }
}

///|
pub fn Plot::new(
  kind : PlotKind,
  title : String,
  unit : String,
  interval_kind : String,
  points : Array[PlotPoint],
) -> Plot {
  { kind, title, unit, interval_kind, points }
}

///|
pub struct PlotDocument {
  schema_version : @model.SchemaVersion
  run_id : String
  target : String
  plots : Array[Plot]
  differential : DifferentialReport
}

///|
pub fn PlotDocument::new(
  run_id : String,
  target : String,
  plots : Array[Plot],
  differential? : DifferentialReport = DifferentialReport::empty(),
) -> PlotDocument {
  {
    schema_version: @model.SchemaVersion::V1,
    run_id,
    target,
    plots,
    differential,
  }
}
