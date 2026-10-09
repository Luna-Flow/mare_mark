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
/// How the x values of a plot are placed along the horizontal axis.
pub(all) enum AxisScale {
  /// Evenly spaced, in order of first appearance; ticks show the x text.
  Categorical
  /// Positioned by numeric value. Every x value must parse as a finite number.
  Linear
  /// Positioned by the logarithm of positive finite numeric values.
  Log
}

///|
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
  { implementation, outcome_kind, count, }
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
  { implementation, minimal_input, fingerprint, shrink_path, replay_command, }
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
  { total, passed, failed, unsupported, expected_difference, }
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
  { mismatches, capabilities, counterexamples, corpus, }
}

///|
pub fn DifferentialReport::empty() -> DifferentialReport {
  DifferentialReport::new([], [], [], CorpusSummary::new(0, 0, 0, 0, 0))
}

///|
pub fn PlotPoint::new(x : String, y : Double, series : String) -> PlotPoint {
  { x, y, series, }
}

///|
pub fn Plot::new(
  kind : PlotKind,
  title : String,
  unit : String,
  interval_kind : String,
  points : Array[PlotPoint],
  x_axis? : AxisScale = Categorical,
  y_axis? : AxisScale = Linear,
  x_label? : String = "",
  note? : String = "",
) -> Plot {
  { kind, title, unit, interval_kind, points, x_axis, y_axis, x_label, note, }
}

///|
pub struct PlotDocument {
  schema_version : @model.SchemaVersion
  run_id : String
  target : String
  plots : Array[Plot]
  differential : DifferentialReport
  comparisons : ComparisonReport
}

///|
pub fn PlotDocument::new(
  run_id : String,
  target : String,
  plots : Array[Plot],
  differential? : DifferentialReport = DifferentialReport::empty(),
  comparisons? : ComparisonReport = ComparisonReport::empty(),
) -> PlotDocument {
  {
    schema_version: @model.SchemaVersion::V2,
    run_id,
    target,
    plots,
    differential,
    comparisons,
  }
}

///|
/// The decision of one paired comparison; the same five outcomes as
/// `@stats.Decision`.
pub(all) enum ComparisonDecision {
  Faster
  Slower
  Equivalent
  Unknown
  Invalid
}

///|
/// Lower-case name of the decision, as written to the plot JSON.
pub fn ComparisonDecision::text(self : ComparisonDecision) -> String {
  match self {
    Faster => "faster"
    Slower => "slower"
    Equivalent => "equivalent"
    Unknown => "unknown"
    Invalid => "invalid"
  }
}

///|
/// Point estimates of one paired comparison over the blocks it used. Times
/// are per-iteration times in µs/op.
pub struct PairedEstimate {
  /// Median of the baseline times of the used blocks.
  baseline_median_us : Double
  /// Median of the candidate times of the used blocks.
  candidate_median_us : Double
  /// Median of the paired deltas `candidate - baseline`.
  median_delta_us : Double
  /// `100 * median_delta_us / baseline_median_us`.
  relative_delta_pct : Double
  /// `baseline_median_us / (baseline_median_us + median_delta_us)`.
  speedup : Double
}

///|
pub fn PairedEstimate::new(
  baseline_median_us : Double,
  candidate_median_us : Double,
  median_delta_us : Double,
  relative_delta_pct : Double,
  speedup : Double,
) -> PairedEstimate {
  {
    baseline_median_us,
    candidate_median_us,
    median_delta_us,
    relative_delta_pct,
    speedup,
  }
}

///|
/// Percentile bootstrap interval of the median paired delta, in µs/op and as a
/// percentage of the baseline median.
pub struct DeltaInterval {
  low_us : Double
  high_us : Double
  low_pct : Double
  high_pct : Double
}

///|
pub fn DeltaInterval::new(
  low_us : Double,
  high_us : Double,
  low_pct : Double,
  high_pct : Double,
) -> DeltaInterval {
  { low_us, high_us, low_pct, high_pct, }
}

///|
/// The paired comparison of one candidate against the baseline at one scale
/// of one case.
pub struct ComparisonRow {
  case_id : String
  scale : String
  baseline : String
  candidate : String
  decision : ComparisonDecision
  /// Why the decision is `Unknown` or `Invalid`; empty otherwise.
  reason : String
  /// `None` when no block was used.
  estimate : PairedEstimate?
  /// `None` when the bootstrap did not run.
  interval : DeltaInterval?
  /// Complete blocks that entered the comparison.
  blocks_used : Int
  /// Blocks without exactly one observation of both implementations.
  blocks_incomplete : Int
  /// Complete blocks removed by the outlier policy.
  blocks_outliers : Int
  /// Bootstrap seed of this row.
  seed : UInt64
}

///|
pub fn ComparisonRow::new(
  case_id : String,
  scale : String,
  baseline : String,
  candidate : String,
  decision : ComparisonDecision,
  reason : String,
  estimate : PairedEstimate?,
  interval : DeltaInterval?,
  blocks_used : Int,
  blocks_incomplete : Int,
  blocks_outliers : Int,
  seed : UInt64,
) -> ComparisonRow {
  {
    case_id,
    scale,
    baseline,
    candidate,
    decision,
    reason,
    estimate,
    interval,
    blocks_used,
    blocks_incomplete,
    blocks_outliers,
    seed,
  }
}

///|
/// The paired comparisons of a report and the settings they were made with.
pub struct ComparisonReport {
  rows : Array[ComparisonRow]
  practical_delta_pct : Double
  /// `OutlierPolicy::text()` of the policy applied to the paired deltas.
  outlier_policy : String
  confidence_pct : Double
  resamples : Int
  /// Fewest used blocks for which a decision is made.
  min_blocks : Int
  run_seed : UInt64
  /// Whether `practical_delta_pct` and `outlier_policy` come from the record.
  protocol_recorded : Bool
  /// Whether `run_seed` comes from the record.
  seed_recorded : Bool
  /// One-line, human-readable statement of the settings and their sources.
  note : String
}

///|
pub fn ComparisonReport::new(
  rows : Array[ComparisonRow],
  practical_delta_pct : Double,
  outlier_policy : String,
  confidence_pct : Double,
  resamples : Int,
  min_blocks : Int,
  run_seed : UInt64,
  protocol_recorded : Bool,
  seed_recorded : Bool,
  note : String,
) -> ComparisonReport {
  {
    rows,
    practical_delta_pct,
    outlier_policy,
    confidence_pct,
    resamples,
    min_blocks,
    run_seed,
    protocol_recorded,
    seed_recorded,
    note,
  }
}

///|
/// No comparisons and an empty note.
pub fn ComparisonReport::empty() -> ComparisonReport {
  ComparisonReport::new([], 0.0, "", 0.0, 0, 0, 0UL, false, false, "")
}
