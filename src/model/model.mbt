///|
pub struct DatasetKey[Scale] {
  scale : Scale
  dataset_id : Int
}

///|
pub fn[Scale] DatasetKey::new(
  scale : Scale,
  dataset_id : Int,
) -> DatasetKey[Scale] {
  { scale, dataset_id }
}

///|
pub struct MeasurementKey {
  dataset_id : Int
  repetition_id : Int
  block_id : Int
}

///|
pub fn MeasurementKey::new(
  dataset_id : Int,
  repetition_id : Int,
  block_id : Int,
) -> MeasurementKey {
  { dataset_id, repetition_id, block_id }
}

///|
pub(all) enum ExperimentDesign {
  FixedDatasetRepeatedMeasurements
  MultipleDatasetsSingleMeasurement
  HierarchicalDatasetsAndRepeats
}

///|
pub struct GenerationContext[Scale] {
  seed : UInt64
  suite_id : String
  case_id : String
  dataset_key : DatasetKey[Scale]
  generator_id : String
  generator_version : String
}

///|
pub fn[Scale] GenerationContext::new(
  seed : UInt64,
  suite_id : String,
  case_id : String,
  dataset_key : DatasetKey[Scale],
  generator_id : String,
  generator_version : String,
) -> GenerationContext[Scale] {
  { seed, suite_id, case_id, dataset_key, generator_id, generator_version }
}

///|
pub(all) enum SetupFrequency {
  PerRun
  PerDataset
  PerImplementation
  PerSample
  PerBatch
  PerIteration
}

///|
pub(all) enum SetupTiming {
  ExcludedFromMeasurement
  IncludedInMeasurement
}

///|
pub(all) enum WorkspaceScope {
  RunWorkspace
  DatasetWorkspace
  ImplementationWorkspace
  SampleWorkspace
  BatchWorkspace
  OperationWorkspace
}

///|
pub struct SetupPolicy {
  frequency : SetupFrequency
  timing : SetupTiming
  workspace_scope : WorkspaceScope
}

///|
pub fn SetupPolicy::new(
  frequency : SetupFrequency,
  timing : SetupTiming,
  workspace_scope : WorkspaceScope,
) -> SetupPolicy {
  { frequency, timing, workspace_scope }
}

///|
pub(all) enum BatchPolicy {
  PerImplementation
  SharedBatchSize
}

///|
pub struct CalibrationProtocol {
  target_batch_time_us : Double
  min_batch_iterations : Int
  max_batch_iterations : Int
  max_sample_time_us : Double
  batch_policy : BatchPolicy
}

///|
pub fn CalibrationProtocol::new(
  target_batch_time_us : Double,
  min_batch_iterations : Int,
  max_batch_iterations : Int,
  max_sample_time_us : Double,
  batch_policy : BatchPolicy,
) -> CalibrationProtocol {
  {
    target_batch_time_us,
    min_batch_iterations,
    max_batch_iterations,
    max_sample_time_us,
    batch_policy,
  }
}

///|
pub enum IntervalMode {
  ExploratoryInterval
  ConfirmatoryInterval
}

///|
pub fn confirmatory_interval() -> IntervalMode {
  ConfirmatoryInterval
}

///|
pub fn exploratory_interval() -> IntervalMode {
  ExploratoryInterval
}

///|
pub(all) enum OrderPolicy {
  BalancedBlocks(UInt64)
  FixedOrder
}

///|
pub(all) enum OutlierPolicy {
  ReportOnly
  TukeyFence
  MADTrim
}

///|
pub(all) enum ValidationCoverage {
  EveryMeasurement
  EveryDataset
  ConfirmatoryOnly
}

///|
pub struct RunProtocol {
  experiment_design : ExperimentDesign
  warmup_iterations : Int
  warmup_time_us : Double?
  calibration : CalibrationProtocol
  practical_delta_pct : Double
  order_policy : OrderPolicy
  outlier_policy : OutlierPolicy
  validation_coverage : ValidationCoverage
  exploratory_samples : Int
  confirmatory_samples : Int
}

///|
pub fn RunProtocol::new(
  experiment_design : ExperimentDesign,
  warmup_iterations : Int,
  warmup_time_us : Double?,
  calibration : CalibrationProtocol,
  practical_delta_pct : Double,
  order_policy : OrderPolicy,
  outlier_policy : OutlierPolicy,
  validation_coverage : ValidationCoverage,
  exploratory_samples : Int,
  confirmatory_samples : Int,
) -> RunProtocol {
  {
    experiment_design,
    warmup_iterations,
    warmup_time_us,
    calibration,
    practical_delta_pct,
    order_policy,
    outlier_policy,
    validation_coverage,
    exploratory_samples,
    confirmatory_samples,
  }
}

///|
pub struct SemanticEnvironment {
  target : String
  toolchain : String
  compiler_flags : String
  dtype_abi : String
}

///|
pub fn SemanticEnvironment::new(
  target : String,
  toolchain : String,
  compiler_flags : String,
  dtype_abi : String,
) -> SemanticEnvironment {
  { target, toolchain, compiler_flags, dtype_abi }
}

///|
pub struct PerformanceEnvironment {
  runtime : String
  cpu : String
  gc : String
  concurrency : Int
  clock : String
  device : String
  frequency_policy : String
}

///|
pub fn PerformanceEnvironment::new(
  runtime : String,
  cpu : String,
  gc : String,
  concurrency : Int,
  clock : String,
  device? : String = "host",
  frequency_policy? : String = "uncontrolled",
) -> PerformanceEnvironment {
  { runtime, cpu, gc, concurrency, clock, device, frequency_policy }
}

///|
pub struct ProvenanceEnvironment {
  os : String
  hostname : String
  timestamp : String
  revision : String
  run_id : String
}

///|
pub fn ProvenanceEnvironment::new(
  os : String,
  hostname : String,
  timestamp : String,
  revision : String,
  run_id : String,
) -> ProvenanceEnvironment {
  { os, hostname, timestamp, revision, run_id }
}

///|
pub struct EnvironmentSnapshot {
  semantic : SemanticEnvironment
  performance : PerformanceEnvironment
  provenance : ProvenanceEnvironment
}

///|
pub fn EnvironmentSnapshot::new(
  semantic : SemanticEnvironment,
  performance : PerformanceEnvironment,
  provenance : ProvenanceEnvironment,
) -> EnvironmentSnapshot {
  { semantic, performance, provenance }
}

///|
pub(all) enum ValidationStatus {
  Valid
  Invalid(String)
  Skipped(String)
  ExpectedDifference(String)
  Unsupported(String)
  InfrastructureFailure(String)
}

///|
pub(all) enum ExecutionOutcome[Value] {
  Value(Value)
  Unsupported(String)
  ParseFailure(String)
  RaisedFlags(Value, Array[String])
  Trapped(String, Array[String])
  Aborted(Int, String)
  Timeout(Int, String)
  ExpectedDifference(String)
}

///|
pub fn[Value] ExecutionOutcome::value(value : Value) -> ExecutionOutcome[Value] {
  Value(value)
}

///|
pub fn[Value] ExecutionOutcome::raised_flags(
  value : Value,
  flags : Array[String],
) -> ExecutionOutcome[Value] {
  RaisedFlags(value, flags)
}

///|
pub fn[Value] ExecutionOutcome::kind(self : ExecutionOutcome[Value]) -> String {
  match self {
    Value(_) => "value"
    Unsupported(_) => "unsupported"
    ParseFailure(_) => "parse_failure"
    RaisedFlags(_, _) => "raised_flags"
    Trapped(_, _) => "trapped"
    Aborted(_, _) => "aborted"
    Timeout(_, _) => "timeout"
    ExpectedDifference(_) => "expected_difference"
  }
}

///|
pub fn[Value] ExecutionOutcome::flags(
  self : ExecutionOutcome[Value],
) -> Array[String] {
  match self {
    RaisedFlags(_, flags) | Trapped(_, flags) => flags
    _ => []
  }
}

///|
pub fn[Value] ExecutionOutcome::value_option(
  self : ExecutionOutcome[Value],
) -> Value? {
  match self {
    Value(value) | RaisedFlags(value, _) => Some(value)
    _ => None
  }
}

///|
pub struct OperationResult[Value, Context] {
  outcome : ExecutionOutcome[Value]
  next_context : Context?
  stdout : String
  stderr : String
  exit_code : Int?
}

///|
pub fn[Value, Context] OperationResult::new(
  outcome : ExecutionOutcome[Value],
  next_context : Context?,
  stdout? : String = "",
  stderr? : String = "",
  exit_code? : Int,
) -> OperationResult[Value, Context] {
  { outcome, next_context, stdout, stderr, exit_code }
}

///|
pub fn[Value, Context] OperationResult::completed(
  value : Value,
  next_context : Context,
) -> OperationResult[Value, Context] {
  OperationResult::new(Value(value), Some(next_context))
}

///|
pub struct CaseDescriptor {
  operation : String
  operands : Array[String]
  context : String
  rounding : String
}

///|
pub fn CaseDescriptor::new(
  operation : String,
  operands : Array[String],
  context : String,
  rounding : String,
) -> CaseDescriptor {
  { operation, operands, context, rounding }
}

///|
pub struct ReplaySpec {
  command : String
  arguments : Array[String]
  timeout_ms : Int
}

///|
pub fn ReplaySpec::new(
  command : String,
  arguments : Array[String],
  timeout_ms? : Int = 5000,
) -> ReplaySpec {
  { command, arguments, timeout_ms }
}

///|
pub(all) struct ValidationEvidence {
  case_id : String
  dataset_id : Int
  step_id : Int
  operation : String
  operands : Array[String]
  context : String
  rounding : String
  expected : String
  actual : String
  expected_kind : String
  actual_kind : String
  expected_flags : Array[String]
  actual_flags : Array[String]
  trap : String
  stderr : String
  exit_code : Int?
  fingerprint : String
  implementation_version : String
  replay : ReplaySpec
}

///|
pub struct Validation {
  status : ValidationStatus
  oracle_id : String
  implementation_id : String
  scale_text : String
  evidence : ValidationEvidence?
}

///|
pub fn Validation::new(
  status : ValidationStatus,
  oracle_id : String,
  implementation_id : String,
  scale_text : String,
) -> Validation {
  { status, oracle_id, implementation_id, scale_text, evidence: None }
}

///|
pub fn Validation::detailed(
  status : ValidationStatus,
  oracle_id : String,
  implementation_id : String,
  scale_text : String,
  evidence : ValidationEvidence,
) -> Validation {
  { status, oracle_id, implementation_id, scale_text, evidence: Some(evidence) }
}

///|
pub struct ValidationFailure {
  validation : Validation
  seed : UInt64
  scale_text : String
  original_fingerprint : String
  minimal_fingerprint : String
  shrink_path : Array[String]
  minimal_input : String
}

///|
pub fn ValidationFailure::new(
  validation : Validation,
  seed : UInt64,
  scale_text : String,
  original_fingerprint : String,
  minimal_fingerprint : String,
  shrink_path : Array[String],
  minimal_input : String,
) -> ValidationFailure {
  {
    validation,
    seed,
    scale_text,
    original_fingerprint,
    minimal_fingerprint,
    shrink_path,
    minimal_input,
  }
}

///|
pub struct Observation {
  case_id : String
  implementation_id : String
  implementation_version : String
  dataset_id : Int
  repetition_id : Int
  block_id : Int
  phase : String
  raw_elapsed_us : Double
  iterations : Int
  batch_sink : String
  setup_timing : SetupTiming
  valid : Bool
}

///|
pub fn Observation::new(
  case_id : String,
  implementation_id : String,
  implementation_version : String,
  dataset_id : Int,
  repetition_id : Int,
  block_id : Int,
  phase : String,
  raw_elapsed_us : Double,
  iterations : Int,
  batch_sink : String,
  setup_timing : SetupTiming,
  valid : Bool,
) -> Observation {
  {
    case_id,
    implementation_id,
    implementation_version,
    dataset_id,
    repetition_id,
    block_id,
    phase,
    raw_elapsed_us,
    iterations,
    batch_sink,
    setup_timing,
    valid,
  }
}

///|
pub struct CalibrationEvent {
  implementation_id : String
  dataset_id : Int
  batch_iterations : Int
  elapsed_us : Double
  target_elapsed_us : Double
  retries : Int
}

///|
pub fn CalibrationEvent::new(
  implementation_id : String,
  dataset_id : Int,
  batch_iterations : Int,
  elapsed_us : Double,
  target_elapsed_us : Double,
  retries : Int,
) -> CalibrationEvent {
  {
    implementation_id,
    dataset_id,
    batch_iterations,
    elapsed_us,
    target_elapsed_us,
    retries,
  }
}

///|
pub struct RunSummary {
  run_id : String
  observation_count : Int
  validation_count : Int
  calibration_count : Int
  complete : Bool
  artifact_location : String?
  passed_count : Int
  failed_count : Int
  unsupported_count : Int
  expected_difference_count : Int
  environment : EnvironmentSnapshot?
}

///|
pub fn RunSummary::new(
  run_id : String,
  observation_count : Int,
  validation_count : Int,
  calibration_count : Int,
  complete : Bool,
  artifact_location : String?,
  passed_count? : Int = 0,
  failed_count? : Int = 0,
  unsupported_count? : Int = 0,
  expected_difference_count? : Int = 0,
  environment? : EnvironmentSnapshot,
) -> RunSummary {
  {
    run_id,
    observation_count,
    validation_count,
    calibration_count,
    complete,
    artifact_location,
    passed_count,
    failed_count,
    unsupported_count,
    expected_difference_count,
    environment,
  }
}

///|
pub struct ScaleBoundary[Scale] {
  below : Scale
  at_or_above : Scale
}

///|
pub fn[Scale] ScaleBoundary::new(
  below : Scale,
  at_or_above : Scale,
) -> ScaleBoundary[Scale] {
  { below, at_or_above }
}

///|
pub struct Region[Key, Choice] {
  lower : Key?
  upper : Key?
  choice : Choice
  evidence_ids : Array[String]
}

///|
pub fn[Key, Choice] Region::new(
  lower : Key?,
  upper : Key?,
  choice : Choice,
  evidence_ids : Array[String],
) -> Region[Key, Choice] {
  { lower, upper, choice, evidence_ids }
}

///|
pub struct ParetoPoint[Key, Choice] {
  key : Key
  choice : Choice
  primary : Double
  secondary : Double
}

///|
pub fn[Key, Choice] ParetoPoint::new(
  key : Key,
  choice : Choice,
  primary : Double,
  secondary : Double,
) -> ParetoPoint[Key, Choice] {
  { key, choice, primary, secondary }
}

///|
pub(all) enum DeploymentPolicy[Key, Choice] {
  Global(Choice)
  Piecewise(Array[Region[Key, Choice]])
  Lookup(Array[(Key, Choice)])
  Pareto(Array[ParetoPoint[Key, Choice]])
  Fallback(Choice, String)
}

///|
pub enum CrossoverResult[Scale] {
  Found(ScaleBoundary[Scale], String, Array[String])
  NoCrossover(String, Array[String])
  NonMonotonic(Array[String])
  Inconclusive(String, Array[String])
}

///|
pub fn[Scale] CrossoverResult::found(
  boundary : ScaleBoundary[Scale],
  policy : String,
  evidence : Array[String],
) -> CrossoverResult[Scale] {
  Found(boundary, policy, evidence)
}

///|
pub fn[Scale] CrossoverResult::no_crossover(
  reason : String,
  evidence : Array[String],
) -> CrossoverResult[Scale] {
  NoCrossover(reason, evidence)
}

///|
pub fn[Scale] CrossoverResult::non_monotonic(
  evidence : Array[String],
) -> CrossoverResult[Scale] {
  NonMonotonic(evidence)
}

///|
pub fn[Scale] CrossoverResult::inconclusive(
  reason : String,
  evidence : Array[String],
) -> CrossoverResult[Scale] {
  Inconclusive(reason, evidence)
}

///|
pub fn protocol_identity(protocol : RunProtocol) -> String {
  "mmk-protocol-v1:" +
  protocol.warmup_iterations.to_string() +
  ":" +
  protocol.confirmatory_samples.to_string() +
  ":" +
  protocol.practical_delta_pct.to_string()
}

///|
pub fn artifact_identity(
  case_id : String,
  implementation_id : String,
  dataset_id : Int,
  protocol : RunProtocol,
) -> String {
  "mmk-artifact-v1:" +
  case_id +
  ":" +
  implementation_id +
  ":" +
  dataset_id.to_string() +
  ":" +
  protocol_identity(protocol)
}

///|
pub fn environment_compatible(
  a : EnvironmentSnapshot,
  b : EnvironmentSnapshot,
) -> Bool {
  a.semantic.target == b.semantic.target &&
  a.semantic.toolchain == b.semantic.toolchain &&
  a.semantic.compiler_flags == b.semantic.compiler_flags &&
  a.semantic.dtype_abi == b.semantic.dtype_abi &&
  a.performance.runtime == b.performance.runtime &&
  a.performance.cpu == b.performance.cpu &&
  a.performance.gc == b.performance.gc &&
  a.performance.concurrency == b.performance.concurrency &&
  a.performance.clock == b.performance.clock &&
  a.performance.device == b.performance.device &&
  a.performance.frequency_policy == b.performance.frequency_policy
}
