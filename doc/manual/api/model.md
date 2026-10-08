# model API

`Luna-Flow/mare_mark/model` is the shared vocabulary of mare_mark: version
identifiers, dataset and measurement keys, run protocols, environment
snapshots, execution outcomes, validation evidence, the event records the
runner emits, and the decision types used by experiments and tuning. It has no
dependencies and no behaviour beyond small accessors and identities. The
reasons behind the shapes are in the [model design](../design/model.md).

Source: [`src/model/model.mbt`](../../../src/model/model.mbt),
[`src/model/versioning.mbt`](../../../src/model/versioning.mbt).

```text
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/runner",
}
```

Most records are `pub struct` with read-only fields and a `new` constructor
whose arguments follow the field order. Enums marked `pub(all)` can be built and
matched by users.

## Versions

### `ProtocolVersion`, `ArtifactVersion`, `SchemaVersion`

These enums name the versioned contracts: the run protocol vocabulary
(`mmkp`), the JSONL artifacts (`mmka`) and the Plot IR schema (`mmks`).

```mbti
pub(all) enum ProtocolVersion {
  V1
}
pub fn ProtocolVersion::identifier(Self) -> String
pub fn ProtocolVersion::implementation(Self) -> String
pub fn ProtocolVersion::lifecycle(Self) -> VersionLifecycle
pub fn ProtocolVersion::version(Self) -> Int

pub(all) enum ArtifactVersion {
  V1
}
pub fn ArtifactVersion::identifier(Self) -> String
pub fn ArtifactVersion::implementation(Self) -> String
pub fn ArtifactVersion::lifecycle(Self) -> VersionLifecycle
pub fn ArtifactVersion::version(Self) -> Int

pub(all) enum SchemaVersion {
  V1
}
pub fn SchemaVersion::identifier(Self) -> String
pub fn SchemaVersion::implementation(Self) -> String
pub fn SchemaVersion::lifecycle(Self) -> VersionLifecycle
pub fn SchemaVersion::version(Self) -> Int
```

`implementation` is the prefix, `version` the number, and `identifier` is
`implementation + "_" + version`. All three `V1` values are `Supported`.

```moonbit
test "version identifiers" {
  inspect(@model.ProtocolVersion::V1.identifier(), content="mmkp_1")
  inspect(@model.ArtifactVersion::V1.identifier(), content="mmka_1")
  inspect(@model.SchemaVersion::V1.identifier(), content="mmks_1")
  inspect(@model.SchemaVersion::V1.lifecycle() is Supported, content="true")
}
```

### `VersionLifecycle`

`VersionLifecycle` says whether a version is still accepted.

```mbti
pub(all) enum VersionLifecycle {
  Supported
  Deprecated
}
```

## Datasets and keys

### `DatasetKey`

`DatasetKey` identifies one dataset of a case: its scale and its index.

```mbti
pub struct DatasetKey[Scale] {
  scale : Scale
  dataset_id : Int
}
pub fn[Scale] DatasetKey::new(Scale, Int) -> Self[Scale]
```

The runner uses the position of the scale in the case's scale list as
`dataset_id`.

### `MeasurementKey`

`MeasurementKey` identifies one measured batch: dataset, repetition and block.

```mbti
pub struct MeasurementKey {
  dataset_id : Int
  repetition_id : Int
  block_id : Int
}
pub fn MeasurementKey::new(Int, Int, Int) -> Self
```

Two measurements are paired when their keys are equal.

### `GenerationContext`

`GenerationContext` is everything an input generator may depend on.

```mbti
pub struct GenerationContext[Scale] {
  seed : UInt64
  suite_id : String
  case_id : String
  dataset_key : DatasetKey[Scale]
  generator_id : String
  generator_version : String
}
pub fn[Scale] GenerationContext::new(UInt64, String, String, DatasetKey[Scale], String, String) -> Self[Scale]
```

A generator that reads only these fields is reproducible. The runner fills
`seed` with the run seed, `suite_id` with `"default"`, and the generator id and
version with the fixture's id and version.

### `CaseDescriptor`

`CaseDescriptor` describes one operation for validation evidence.

```mbti
pub struct CaseDescriptor {
  operation : String
  operands : Array[String]
  context : String
  rounding : String
}
pub fn CaseDescriptor::new(String, Array[String], String, String) -> Self
```

## Run protocol

### `RunProtocol`

`RunProtocol` is the complete measurement protocol of a run.

```mbti
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
pub fn RunProtocol::new(ExperimentDesign, Int, Double?, CalibrationProtocol, Double, OrderPolicy, OutlierPolicy, ValidationCoverage, Int, Int) -> Self
```

The runner acts on the warmup, calibration, order and sample-count fields; the
others record the intended analysis. `@runner.validate_protocol` checks the
values, and `@runner.ProtocolPreset` provides three complete protocols.

### `CalibrationProtocol`

`CalibrationProtocol` controls how many iterations a timed batch contains.

```mbti
pub struct CalibrationProtocol {
  target_batch_time_us : Double
  min_batch_iterations : Int
  max_batch_iterations : Int
  max_sample_time_us : Double
  batch_policy : BatchPolicy
}
pub fn CalibrationProtocol::new(Double, Int, Int, Double, BatchPolicy) -> Self
```

Calibration grows the batch from `min_batch_iterations` until it lasts
`target_batch_time_us`, reaches `max_batch_iterations` or exceeds
`max_sample_time_us`.

### Protocol enums

```mbti
pub(all) enum ExperimentDesign {
  FixedDatasetRepeatedMeasurements
  MultipleDatasetsSingleMeasurement
  HierarchicalDatasetsAndRepeats
}

pub(all) enum BatchPolicy {
  PerImplementation
  SharedBatchSize
}

pub(all) enum OrderPolicy {
  BalancedBlocks(UInt64)
  FixedOrder
}

pub(all) enum OutlierPolicy {
  ReportOnly
  TukeyFence
  MADTrim
}

pub(all) enum ValidationCoverage {
  EveryMeasurement
  EveryDataset
  ConfirmatoryOnly
}
```

| Enum | Meaning |
| --- | --- |
| `ExperimentDesign` | the intended sampling structure: repeated measurements of one dataset, one measurement of many datasets, or both |
| `BatchPolicy` | calibrate each implementation separately, or give all the smallest calibrated size |
| `OrderPolicy` | rotate implementation order per block with a seed, or keep the declared order |
| `OutlierPolicy` | the outlier view for analysis: none, Tukey fences, or 3 MAD around the median (see `@stats.filter_outliers`) |
| `ValidationCoverage` | the intended validation frequency |

### `IntervalMode`, `confirmatory_interval`, `exploratory_interval`

`IntervalMode` labels an interval with the phase whose data produced it.

```mbti
pub enum IntervalMode {
  ExploratoryInterval
  ConfirmatoryInterval
}
pub fn confirmatory_interval() -> IntervalMode
pub fn exploratory_interval() -> IntervalMode
```

The enum is readonly outside the package; obtain values from the two
functions.

### Setup policy

`SetupPolicy` tells the runner how often a fixture prepares its input and
whether that work is timed.

```mbti
pub struct SetupPolicy {
  frequency : SetupFrequency
  timing : SetupTiming
  workspace_scope : WorkspaceScope
}
pub fn SetupPolicy::new(SetupFrequency, SetupTiming, WorkspaceScope) -> Self

pub(all) enum SetupFrequency {
  PerRun
  PerDataset
  PerImplementation
  PerSample
  PerBatch
  PerIteration
}

pub(all) enum SetupTiming {
  ExcludedFromMeasurement
  IncludedInMeasurement
}

pub(all) enum WorkspaceScope {
  RunWorkspace
  DatasetWorkspace
  ImplementationWorkspace
  SampleWorkspace
  BatchWorkspace
  OperationWorkspace
}
```

`frequency` and `timing` change what the runner times (the
[runner design](../design/runner.md) has the exact table);
`workspace_scope` documents how long a workspace lives and is not interpreted.

## Environment

### `EnvironmentSnapshot`

`EnvironmentSnapshot` records where a run happened, in three parts.

```mbti
pub struct EnvironmentSnapshot {
  semantic : SemanticEnvironment
  performance : PerformanceEnvironment
  provenance : ProvenanceEnvironment
}
pub fn EnvironmentSnapshot::new(SemanticEnvironment, PerformanceEnvironment, ProvenanceEnvironment) -> Self
```

### `SemanticEnvironment`

`SemanticEnvironment` holds what can change results, not only timings.

```mbti
pub struct SemanticEnvironment {
  target : ExecutionTarget
  toolchain : String
  compiler_flags : String
  dtype_abi : String
}
pub fn SemanticEnvironment::new(ExecutionTarget, String, String, String) -> Self
```

### `PerformanceEnvironment`

`PerformanceEnvironment` holds what changes timings.

```mbti
pub struct PerformanceEnvironment {
  runtime : String
  cpu : String
  gc : String
  concurrency : Int
  clock : String
  device : String
  frequency_policy : String
}
pub fn PerformanceEnvironment::new(String, String, String, Int, String, device? : String, frequency_policy? : String) -> Self
```

`device` defaults to `"host"` and `frequency_policy` to `"uncontrolled"`.

### `ProvenanceEnvironment`

`ProvenanceEnvironment` holds where and when a run happened.

```mbti
pub struct ProvenanceEnvironment {
  os : String
  hostname : String
  timestamp : String
  revision : String
  run_id : String
}
pub fn ProvenanceEnvironment::new(String, String, String, String, String) -> Self
```

### `ExecutionTarget`

`ExecutionTarget` names the MoonBit backend.

```mbti
pub(all) enum ExecutionTarget {
  Native
  Js
  Wasm
  WasmGc
  Llvm
  Custom(String)
}
pub fn ExecutionTarget::text(Self) -> String
```

`text` gives `"native"`, `"js"`, `"wasm"`, `"wasm-gc"`, `"llvm"` or the custom
string.

### `environment_compatible`

`environment_compatible` reports whether timings from two environments may be
compared.

```mbti
pub fn environment_compatible(EnvironmentSnapshot, EnvironmentSnapshot) -> Bool
```

It is true when every semantic and performance field is equal; provenance is
ignored.

```moonbit
test "provenance does not matter, the CPU does" {
  let semantic = @model.SemanticEnvironment::new(@model.ExecutionTarget::Native, "moonc", "", "f64")
  let cpu_a = @model.PerformanceEnvironment::new("native", "cpu-a", "default", 1, "monotonic")
  let cpu_b = @model.PerformanceEnvironment::new("native", "cpu-b", "default", 1, "monotonic")
  let monday = @model.ProvenanceEnvironment::new("linux", "ci-1", "monday", "abc", "run-1")
  let tuesday = @model.ProvenanceEnvironment::new("linux", "ci-2", "tuesday", "def", "run-2")
  let a1 = @model.EnvironmentSnapshot::new(semantic, cpu_a, monday)
  let a2 = @model.EnvironmentSnapshot::new(semantic, cpu_a, tuesday)
  let b = @model.EnvironmentSnapshot::new(semantic, cpu_b, monday)
  inspect(@model.environment_compatible(a1, a2), content="true")
  inspect(@model.environment_compatible(a1, b), content="false")
}
```

## Identities

### `protocol_identity`

`protocol_identity` returns a short key for a protocol.

```mbti
pub fn protocol_identity(RunProtocol) -> String
```

The key is `mmkp_1:<warmup_iterations>:<confirmatory_samples>:<practical_delta_pct>`.
Only these three fields enter it; protocols that differ elsewhere share a key.

### `artifact_identity`

`artifact_identity` returns a key for the artifacts of one case,
implementation and dataset under a protocol.

```mbti
pub fn artifact_identity(String, String, Int, RunProtocol) -> String
```

The key is `mmka_1:<case>:<implementation>:<dataset_id>:` followed by the
protocol identity.

```moonbit
test "identities" {
  let protocol = @runner.ProtocolPreset::Development.validated().protocol
  inspect(@model.protocol_identity(protocol), content="mmkp_1:3:10:1")
  inspect(@model.artifact_identity("sum", "loop", 2, protocol), content="mmka_1:sum:loop:2:mmkp_1:3:10:1")
}
```

## Outcomes

### `ExecutionOutcome`

`ExecutionOutcome` is what one operation produced.

```mbti
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
pub fn[Value] ExecutionOutcome::value(Value) -> Self[Value]
pub fn[Value] ExecutionOutcome::raised_flags(Value, Array[String]) -> Self[Value]
pub fn[Value] ExecutionOutcome::kind(Self[Value]) -> String
pub fn[Value] ExecutionOutcome::flags(Self[Value]) -> Array[String]
pub fn[Value] ExecutionOutcome::value_option(Self[Value]) -> Value?
```

| Constructor | Meaning | `kind` |
| --- | --- | --- |
| `Value(v)` | a result | `value` |
| `RaisedFlags(v, flags)` | a result with status flags (for example IEEE exceptions) | `raised_flags` |
| `Trapped(trap, flags)` | the operation trapped | `trapped` |
| `Unsupported(reason)` | the implementation does not support this input | `unsupported` |
| `ExpectedDifference(reason)` | a documented, accepted deviation | `expected_difference` |
| `ParseFailure(reason)` | the result could not be decoded | `parse_failure` |
| `Aborted(exit_code, stderr)` | a worker process failed | `aborted` |
| `Timeout(ms, reason)` | a worker exceeded its timeout | `timeout` |

`value_option` returns the value of `Value` and `RaisedFlags`, otherwise
`None`; `flags` returns the flags of `RaisedFlags` and `Trapped`, otherwise
`[]`.

```moonbit
test "outcomes" {
  let flagged = @model.ExecutionOutcome::raised_flags(1.0, ["inexact"])
  inspect(flagged.kind(), content="raised_flags")
  debug_inspect(flagged.value_option(), content="Some(1)")
  let timeout : @model.ExecutionOutcome[Double] = Timeout(100, "slow")
  inspect(timeout.value_option() is None, content="true")
}
```

### `OperationResult`

`OperationResult` is an outcome together with the context for the next
operation and captured process output.

```mbti
pub struct OperationResult[Value, Context] {
  outcome : ExecutionOutcome[Value]
  next_context : Context?
  stdout : String
  stderr : String
  exit_code : Int?
}
pub fn[Value, Context] OperationResult::new(ExecutionOutcome[Value], Context?, stdout? : String, stderr? : String, exit_code? : Int) -> Self[Value, Context]
pub fn[Value, Context] OperationResult::completed(Value, Context) -> Self[Value, Context]
```

`completed(v, c)` is `new(Value(v), Some(c))`. `next_context = None` ends a
sequence. `stdout` and `stderr` default to `""`.

## Validation

### `ValidationStatus`

`ValidationStatus` is the verdict of an oracle on one step.

```mbti
pub(all) enum ValidationStatus {
  Valid
  Invalid(String)
  Skipped(String)
  ExpectedDifference(String)
  Unsupported(String)
  InfrastructureFailure(String)
}
```

The runner counts `Valid` as passed, `Invalid` and `InfrastructureFailure` as
failed, `Unsupported` and `Skipped` as unsupported, and `ExpectedDifference`
separately.

### `Validation`

`Validation` is one validation event.

```mbti
pub struct Validation {
  status : ValidationStatus
  oracle_id : String
  implementation_id : String
  scale_text : String
  evidence : ValidationEvidence?
}
pub fn Validation::new(ValidationStatus, String, String, String) -> Self
pub fn Validation::detailed(ValidationStatus, String, String, String, ValidationEvidence) -> Self
```

`new` leaves `evidence` empty; `detailed` attaches it.

### `ValidationEvidence`

`ValidationEvidence` is everything needed to understand and replay one
validated step.

```mbti
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
```

It is `pub(all)`: build it with a struct literal.

### `ValidationFailure`

`ValidationFailure` is a failed validation with its minimized input.

```mbti
pub struct ValidationFailure {
  validation : Validation
  seed : UInt64
  scale_text : String
  original_fingerprint : String
  minimal_fingerprint : String
  shrink_path : Array[String]
  minimal_input : String
}
pub fn ValidationFailure::new(Validation, UInt64, String, String, String, Array[String], String) -> Self
```

### `ReplaySpec`

`ReplaySpec` is a command that reproduces a failure.

```mbti
pub struct ReplaySpec {
  command : String
  arguments : Array[String]
  timeout_ms : Int
}
pub fn ReplaySpec::new(String, Array[String], timeout_ms? : Int) -> Self
```

`timeout_ms` defaults to `5000`. `mare-mark replay` executes it.

## Run events

### `Observation`

`Observation` is one timed batch.

```mbti
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
pub fn Observation::new(String, String, String, Int, Int, Int, ObservationPhase, Double, Int, BatchSinkStatus, SetupTiming, Bool) -> Self
```

`raw_elapsed_us` is the batch time divided by `iterations`, in µs per
operation; it is not filtered or aggregated across batches. `repetition_id`
counts blocks within the phase, `block_id` counts them across both phases.

### `ObservationPhase`

```mbti
pub(all) enum ObservationPhase {
  Exploratory
  Confirmatory
}
pub fn ObservationPhase::text(Self) -> String
```

`text` gives `"exploratory"` or `"confirmatory"`.

### `BatchSinkStatus`

`BatchSinkStatus` records whether a batch is kept for analysis.

```mbti
pub(all) enum BatchSinkStatus {
  Kept
  Discarded(String)
}
pub fn BatchSinkStatus::text(Self) -> String
```

`text` gives `"kept"` or `"discarded:<reason>"`. The runner emits `Kept`;
reports skip discarded batches.

### `CalibrationEvent`

`CalibrationEvent` records the batch size chosen for one implementation and
dataset.

```mbti
pub struct CalibrationEvent {
  implementation_id : String
  dataset_id : Int
  batch_iterations : Int
  elapsed_us : Double
  target_elapsed_us : Double
  retries : Int
}
pub fn CalibrationEvent::new(String, Int, Int, Double, Double, Int) -> Self
```

`elapsed_us` is the time of the last calibration batch.

### `RunSummary`

`RunSummary` closes a run.

```mbti
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
pub fn RunSummary::new(String, Int, Int, Int, Bool, String?, passed_count? : Int, failed_count? : Int, unsupported_count? : Int, expected_difference_count? : Int, environment? : EnvironmentSnapshot) -> Self
```

The counts default to `0` and `environment` to `None`.

## Decisions and deployment

### `ScaleBoundary`

`ScaleBoundary` is the place where the preferred implementation changes.

```mbti
pub struct ScaleBoundary[Scale] {
  below : Scale
  at_or_above : Scale
}
pub fn[Scale] ScaleBoundary::new(Scale, Scale) -> Self[Scale]
```

### `CrossoverResult`

`CrossoverResult` is the outcome of a crossover search over scales.

```mbti
pub enum CrossoverResult[Scale] {
  Found(ScaleBoundary[Scale], String, Array[String])
  NoCrossover(String, Array[String])
  NonMonotonic(Array[String])
  Inconclusive(String, Array[String])
}
pub fn[Scale] CrossoverResult::found(ScaleBoundary[Scale], String, Array[String]) -> Self[Scale]
pub fn[Scale] CrossoverResult::no_crossover(String, Array[String]) -> Self[Scale]
pub fn[Scale] CrossoverResult::non_monotonic(Array[String]) -> Self[Scale]
pub fn[Scale] CrossoverResult::inconclusive(String, Array[String]) -> Self[Scale]
```

The strings are a policy or reason, and the arrays are evidence (the labels or
ids the result is based on). The enum is readonly outside the package; build
it with the four functions. `@experiment.crossover_from_labels` produces it.

### `Region`

`Region` assigns a choice to a range of keys.

```mbti
pub struct Region[Key, Choice] {
  lower : Key?
  upper : Key?
  choice : Choice
  evidence_ids : Array[String]
}
pub fn[Key, Choice] Region::new(Key?, Key?, Choice, Array[String]) -> Self[Key, Choice]
```

`None` bounds are open.

### `ParetoPoint`

`ParetoPoint` is a choice with two costs.

```mbti
pub struct ParetoPoint[Key, Choice] {
  key : Key
  choice : Choice
  primary : Double
  secondary : Double
}
pub fn[Key, Choice] ParetoPoint::new(Key, Choice, Double, Double) -> Self[Key, Choice]
```

### `DeploymentPolicy`

`DeploymentPolicy` is how a tuning or crossover result is used in production.

```mbti
pub(all) enum DeploymentPolicy[Key, Choice] {
  Global(Choice)
  Piecewise(Array[Region[Key, Choice]])
  Lookup(Array[(Key, Choice)])
  Pareto(Array[ParetoPoint[Key, Choice]])
  Fallback(Choice, String)
}
```

| Constructor | Use |
| --- | --- |
| `Global(c)` | one choice everywhere |
| `Piecewise(regions)` | a choice per key range, for example below and above a crossover |
| `Lookup(pairs)` | a choice per measured key |
| `Pareto(points)` | the non-dominated trade-offs, left to the caller |
| `Fallback(c, reason)` | a safe default when the evidence is insufficient |

```moonbit
test "a piecewise policy from a crossover" {
  let boundary = @model.ScaleBoundary::new(256, 512)
  let policy : @model.DeploymentPolicy[Int, String] = Piecewise([
    @model.Region::new(None, Some(boundary.below), "insertion", ["run-1"]),
    @model.Region::new(Some(boundary.at_or_above), None, "merge", ["run-1"]),
  ])
  guard policy is Piecewise(regions) else { fail("expected regions") }
  inspect(regions[1].choice, content="merge")
}
```
