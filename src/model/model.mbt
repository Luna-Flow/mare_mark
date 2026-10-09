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
  { scale, dataset_id, }
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
  { dataset_id, repetition_id, block_id, }
}

///|
pub(all) enum ExperimentDesign {
  FixedDatasetRepeatedMeasurements
  MultipleDatasetsSingleMeasurement
  HierarchicalDatasetsAndRepeats
}

///|
/// Stable snake_case tag, used by `protocol_canonical_encoding` and the JSONL
/// `protocol` object.
pub fn ExperimentDesign::text(self : ExperimentDesign) -> String {
  match self {
    FixedDatasetRepeatedMeasurements => "fixed_dataset_repeated_measurements"
    MultipleDatasetsSingleMeasurement => "multiple_datasets_single_measurement"
    HierarchicalDatasetsAndRepeats => "hierarchical_datasets_and_repeats"
  }
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
  { seed, suite_id, case_id, dataset_key, generator_id, generator_version, }
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
  { frequency, timing, workspace_scope, }
}

///|
pub(all) enum BatchPolicy {
  PerImplementation
  SharedBatchSize
}

///|
/// Stable snake_case tag, used by `protocol_canonical_encoding` and the JSONL
/// `protocol` object.
pub fn BatchPolicy::text(self : BatchPolicy) -> String {
  match self {
    PerImplementation => "per_implementation"
    SharedBatchSize => "shared_batch_size"
  }
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
/// Stable snake_case tag, used by `protocol_canonical_encoding` and the JSONL
/// `protocol` object.
pub fn OutlierPolicy::text(self : OutlierPolicy) -> String {
  match self {
    ReportOnly => "report_only"
    TukeyFence => "tukey_fence"
    MADTrim => "mad_trim"
  }
}

///|
pub(all) enum ValidationCoverage {
  EveryMeasurement
  EveryDataset
  ConfirmatoryOnly
}

///|
/// Stable snake_case tag, used by `protocol_canonical_encoding` and the JSONL
/// `protocol` object.
pub fn ValidationCoverage::text(self : ValidationCoverage) -> String {
  match self {
    EveryMeasurement => "every_measurement"
    EveryDataset => "every_dataset"
    ConfirmatoryOnly => "confirmatory_only"
  }
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
pub(all) enum ExecutionTarget {
  Native
  Js
  Wasm
  WasmGc
  Llvm
  Custom(String)
}

///|
pub fn ExecutionTarget::text(self : ExecutionTarget) -> String {
  match self {
    Native => "native"
    Js => "js"
    Wasm => "wasm"
    WasmGc => "wasm-gc"
    Llvm => "llvm"
    Custom(target) => target
  }
}

///|
fn execution_target_equal(a : ExecutionTarget, b : ExecutionTarget) -> Bool {
  match (a, b) {
    (Native, Native)
    | (Js, Js)
    | (Wasm, Wasm)
    | (WasmGc, WasmGc)
    | (Llvm, Llvm) => true
    (Custom(left), Custom(right)) => left == right
    _ => false
  }
}

///|
pub struct SemanticEnvironment {
  target : ExecutionTarget
  toolchain : String
  compiler_flags : String
  dtype_abi : String
}

///|
pub fn SemanticEnvironment::new(
  target : ExecutionTarget,
  toolchain : String,
  compiler_flags : String,
  dtype_abi : String,
) -> SemanticEnvironment {
  { target, toolchain, compiler_flags, dtype_abi, }
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
  { runtime, cpu, gc, concurrency, clock, device, frequency_policy, }
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
  { os, hostname, timestamp, revision, run_id, }
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
  { semantic, performance, provenance, }
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
  { outcome, next_context, stdout, stderr, exit_code, }
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
  { operation, operands, context, rounding, }
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
  { command, arguments, timeout_ms, }
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
  { status, oracle_id, implementation_id, scale_text, evidence: None, }
}

///|
pub fn Validation::detailed(
  status : ValidationStatus,
  oracle_id : String,
  implementation_id : String,
  scale_text : String,
  evidence : ValidationEvidence,
) -> Validation {
  {
    status,
    oracle_id,
    implementation_id,
    scale_text,
    evidence: Some(evidence),
  }
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
  phase : ObservationPhase
  raw_elapsed_us : Double
  iterations : Int
  batch_sink : BatchSinkStatus
  setup_timing : SetupTiming
  valid : Bool
}

///|
pub(all) enum ObservationPhase {
  Exploratory
  Confirmatory
}

///|
pub fn ObservationPhase::text(self : ObservationPhase) -> String {
  match self {
    Exploratory => "exploratory"
    Confirmatory => "confirmatory"
  }
}

///|
pub(all) enum BatchSinkStatus {
  Kept
  Discarded(String)
}

///|
pub fn BatchSinkStatus::text(self : BatchSinkStatus) -> String {
  match self {
    Kept => "kept"
    Discarded(reason) => "discarded:" + reason
  }
}

///|
pub fn Observation::new(
  case_id : String,
  implementation_id : String,
  implementation_version : String,
  dataset_id : Int,
  repetition_id : Int,
  block_id : Int,
  phase : ObservationPhase,
  raw_elapsed_us : Double,
  iterations : Int,
  batch_sink : BatchSinkStatus,
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
/// Outcome of one run.
///
/// `run_id` is built by the runner with `run_identity`: case id, protocol
/// identity, run seed, and the provenance `run_id` and `timestamp` of the
/// environment. `protocol` and `seed` record what the run was executed with,
/// so a JSONL record can be audited and re-analysed; both are `None` for
/// summaries built without them.
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
  protocol : RunProtocol?
  seed : UInt64?
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
  protocol? : RunProtocol,
  seed? : UInt64,
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
    protocol,
    seed,
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
  { below, at_or_above, }
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
  { lower, upper, choice, evidence_ids, }
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
  { key, choice, primary, secondary, }
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
/// Exact text of a `Double`: `0x` and the 16 hex digits of its IEEE 754 bit
/// pattern. Independent of decimal formatting, distinguishes `-0.0` from
/// `0.0`, and is the same on every backend.
fn canonical_double(value : Double) -> String {
  "0x" + hex16(value.reinterpret_as_uint64())
}

///|
fn hex16(value : UInt64) -> String {
  let buffer = StringBuilder()
  for shift = 60; shift >= 0; shift = shift - 4 {
    let nibble = ((value >> shift) & 15UL).to_int()
    let code = if nibble < 10 { 48 + nibble } else { 87 + nibble }
    buffer.write_char(code.unsafe_to_char())
  }
  buffer.to_string()
}

///|
/// The `RunProtocol` fields in canonical order as `(key, value)` pairs.
///
/// Every field appears exactly once, nested fields with a dotted key. Values
/// are decimal integers, `canonical_double` texts, `none` / `some(...)` for
/// options, and `text()` tags for enums; `OrderPolicy` is `fixed_order` or
/// `balanced_blocks(<seed>)`. A new `RunProtocol` field is one more line here.
fn protocol_canonical_fields(protocol : RunProtocol) -> Array[(String, String)] {
  let calibration = protocol.calibration
  [
    ("experiment_design", protocol.experiment_design.text()),
    ("warmup_iterations", protocol.warmup_iterations.to_string()),
    (
      "warmup_time_us",
      match protocol.warmup_time_us {
        None => "none"
        Some(value) => "some(" + canonical_double(value) + ")"
      },
    ),
    (
      "calibration.target_batch_time_us",
      canonical_double(calibration.target_batch_time_us),
    ),
    (
      "calibration.min_batch_iterations",
      calibration.min_batch_iterations.to_string(),
    ),
    (
      "calibration.max_batch_iterations",
      calibration.max_batch_iterations.to_string(),
    ),
    (
      "calibration.max_sample_time_us",
      canonical_double(calibration.max_sample_time_us),
    ),
    ("calibration.batch_policy", calibration.batch_policy.text()),
    ("practical_delta_pct", canonical_double(protocol.practical_delta_pct)),
    (
      "order_policy",
      match protocol.order_policy {
        FixedOrder => "fixed_order"
        BalancedBlocks(seed) => "balanced_blocks(" + seed.to_string() + ")"
      },
    ),
    ("outlier_policy", protocol.outlier_policy.text()),
    ("validation_coverage", protocol.validation_coverage.text()),
    ("exploratory_samples", protocol.exploratory_samples.to_string()),
    ("confirmatory_samples", protocol.confirmatory_samples.to_string()),
  ]
}

///|
/// Canonical, unambiguous ASCII encoding of every `RunProtocol` field:
/// `mmkp_2` followed by `;<key>=<value>` for each field in a fixed order.
///
/// Keys are fixed and values never contain `;` or `=`, so two protocols have
/// the same encoding exactly when every field is equal (doubles compared by
/// bit pattern). `protocol_identity` is a digest of this text.
pub fn protocol_canonical_encoding(protocol : RunProtocol) -> String {
  let buffer = StringBuilder()
  buffer.write_string(ProtocolVersion::V2.identifier())
  for field in protocol_canonical_fields(protocol) {
    let (key, value) = field
    buffer.write_char(';')
    buffer.write_string(key)
    buffer.write_char('=')
    buffer.write_string(value)
  }
  buffer.to_string()
}

///|
/// 64-bit FNV-1a over the code units of an ASCII string.
fn fnv1a64(text : String) -> UInt64 {
  let mut hash = 0xCBF29CE484222325UL
  for index = 0; index < text.length(); index = index + 1 {
    hash = (hash ^ text[index].to_int().to_uint64()) * 0x100000001B3UL
  }
  hash
}

///|
/// Identity of a run protocol: `mmkp_2:<16 lowercase hex digits>`, the 64-bit
/// FNV-1a digest of `protocol_canonical_encoding(protocol)`.
///
/// It covers every `RunProtocol` field, including the calibration, the
/// `BalancedBlocks` seed and the optional warm-up time. Equal protocols get
/// equal identities; protocols that differ in any field get different ones
/// (up to 64-bit digest collisions). Use `protocol_canonical_encoding` or the
/// JSONL `protocol` object to see the fields behind an identity.
pub fn protocol_identity(protocol : RunProtocol) -> String {
  ProtocolVersion::V2.identifier() +
  ":" +
  hex16(fnv1a64(protocol_canonical_encoding(protocol)))
}

///|
fn escape_run_component(text : String) -> String {
  text.replace_all(old="%", new="%25").replace_all(old="|", new="%7C")
}

///|
/// `RunSummary.run_id` of one run: five components joined by `|`, in order
///
/// 1. the case id,
/// 2. `protocol_identity(protocol)`,
/// 3. the run seed in decimal,
/// 4. the provenance `run_id` of the environment,
/// 5. the provenance `timestamp` of the environment.
///
/// `%` and `|` inside the case id, provenance run id and timestamp are written
/// as `%25` and `%7C`, so the components can be recovered by splitting on `|`.
/// Two runs of the same case and protocol get different ids when their seeds,
/// provenance run ids or timestamps differ.
pub fn run_identity(
  case_id : String,
  protocol : RunProtocol,
  seed : UInt64,
  provenance : ProvenanceEnvironment,
) -> String {
  [
    escape_run_component(case_id),
    protocol_identity(protocol),
    seed.to_string(),
    escape_run_component(provenance.run_id),
    escape_run_component(provenance.timestamp),
  ].join("|")
}

///|
pub fn artifact_identity(
  case_id : String,
  implementation_id : String,
  dataset_id : Int,
  protocol : RunProtocol,
) -> String {
  ArtifactVersion::V1.identifier() +
  ":" +
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
  execution_target_equal(a.semantic.target, b.semantic.target) &&
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
