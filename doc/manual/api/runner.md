# runner API

## Purpose

`Luna-Flow/mare_mark/runner` owns the measurement loop. You describe a
benchmark case, compile it into a validated plan, and `run` it with a seed, an
environment snapshot, an event sink and a validated protocol. The runner
validates every implementation against an oracle before timing, calibrates the
batch size, measures in balanced blocks and emits raw events. The reasons for
each step are in the [runner design](../design/runner.md).

Source: [`src/runner/runner.mbt`](../../../src/runner/runner.mbt),
[`src/runner/bench_spec.mbt`](../../../src/runner/bench_spec.mbt).

## Importing

Add the packages to the `moon.pkg` of the package that uses them:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/runner",
  "Luna-Flow/mare_mark/fixture",
  "Luna-Flow/mare_mark/experiment",
  "moonbitlang/async",
}
```

The examples on this page call them through their default aliases (`@model`,
`@event`, `@runner`, `@fixture`, `@experiment`, `@async`); `fixture` and
`experiment` are needed only to build a case with `BenchSpec::advanced`.

## Asynchrony and type parameters

`run` and `execute_operation` are `async`. Call them from an `async fn main`
or an `async test`; the `moonbitlang/async` runtime that drives them is
available on the native, JS and wasm targets, not on wasm-gc. Subprocess
workers need the native target. Like every `async` function, `run` may raise;
the error it raises itself is `RunConfigError`.

The type parameters recur throughout the package:

| Parameter | Meaning |
| --- | --- |
| `Scale` | the size parameter of a dataset, for example `Int` |
| `Input` | the value a fixture materializes for one dataset |
| `Prepared` | the value an implementation runs on, produced by the fixture's `prepare` |
| `Expected` | what the reference oracle computes |
| `Output` | what an implementation returns |
| `Context` | state threaded from one operation to the next (`Unit` when stateless) |
| `State`, `SinkValue` | accumulator and final value of the `OutputSink` |

## Running a plan

### `run`

`run` executes a compiled plan and returns the run summary.

```mbti
pub async fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] run(ValidatedBenchPlan[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue], RunContext) -> @model.RunSummary
```

Before anything runs, `run` checks the plan against the protocol of the
context and raises `RunConfigError` when they do not fit together (a
`PerRun` fixture with more than one dataset, see `BenchSpec::compile`);
nothing is emitted in that case.

For every scale, in the order of the case, the runner goes through the
datasets of that scale. The protocol's `experiment_design` decides how many
there are and which blocks measure each. With $E$ = `exploratory_samples`,
$C$ = `confirmatory_samples` and $r$ = `repeats_per_dataset`, the blocks of a
scale are numbered $b = 0, \dots, E + C - 1$ (exploratory first) and

| `experiment_design` | Datasets per scale $D$ | Dataset index of block $b$ |
| --- | --- | --- |
| `FixedDatasetRepeatedMeasurements` | $1$ | $0$ |
| `MultipleDatasetsSingleMeasurement` | $E + C$ | $b$ |
| `HierarchicalDatasetsAndRepeats` | $(E + C) / r$ | $\lfloor b / r \rfloor$ |

The dataset with index $j$ of the scale at position $s$ has
`dataset_id` $= s \cdot D + j$, unique within the run. For each dataset the
runner materializes the input, validates the implementations against the
oracle if `validation_coverage` asks for it, warms up and calibrates every
implementation if it is the first dataset of the scale (the batch sizes then
apply to all datasets of the scale), and measures the dataset's blocks: one
batch per implementation per block, in the order of `balanced_order`. Every
validation, failure, calibration and observation is sent to the sink as it
happens; the summary is sent last, and the location string returned by the
sink's `finish` becomes `artifact_location` of the returned summary.

The returned `RunSummary` has `complete == true`, the event counts, the
validation tallies (`passed_count`, `failed_count`, `unsupported_count`,
`expected_difference_count`, `measurement_validation_count`), the
environment, the protocol and the seed. Its `run_id` is
`@model.run_identity(case_id, protocol, seed, environment.provenance)`, so it
is unique when the environment's provenance `run_id` is
(`@env_detect.detect` makes a fresh one).

A validation failure does not stop the measurement: the implementation is
still timed and the failure is reported, so that a report can show the
mismatch next to the series it invalidates.

```moonbit
fn environment() -> @model.EnvironmentSnapshot {
  @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(@model.ExecutionTarget::Native, "moonc 0.10", "", "i32"),
    @model.PerformanceEnvironment::new("native", "laptop", "default", 1, "monotonic"),
    @model.ProvenanceEnvironment::new("macos", "host", "2026-10-08T00:00:00Z", "HEAD", "run-1"),
  )
}

async test "run a plan" {
  let square = @runner.Implementation::stateless("square", "1", (x : Int) => {
    @model.OperationResult::completed(x * x, ())
  })
  let plan = @runner.single_step("square", [2, 3])
    .with_immutable_input(context => context.dataset_key.scale, x => x.to_string())
    .compare([square])
    .against_equal(x => x * x, (expected, actual) => expected == actual)
    .compile()
    .unwrap()
  let memory = @event.InMemorySink::new()
  let summary = @runner.run(
    plan,
    @runner.RunContext::new(
      environment(),
      memory.as_sink(),
      42UL,
      @runner.ProtocolPreset::QuickCheck.validated(),
    ),
  )
  inspect(summary.run_id, content="square|mmkp_2:a8272a0d9e84b872|42|run-1|2026-10-08T00:00:00Z")
  inspect(summary.passed_count, content="2")
  inspect(summary.observation_count, content="8")
  debug_inspect(summary.seed, content="Some(42)")
  inspect(summary.artifact_location.unwrap(), content="memory://run/square|mmkp_2:a8272a0d9e84b872|42|run-1|2026-10-08T00:00:00Z")
}
```

With `QuickCheck` there is one exploratory and three confirmatory block per
scale, so two scales and one implementation give eight observations. The
example writes the environment by hand so that the run id is the same every
time; a real run would use `@env_detect.detect`.

### `RunContext`

`RunContext` carries everything a run needs besides the plan.

```mbti
pub struct RunContext {
  seed : UInt64
  environment : @model.EnvironmentSnapshot
  sink : @event.ObservationSink
  protocol : ValidatedProtocol
}
pub fn RunContext::new(@model.EnvironmentSnapshot, @event.ObservationSink, UInt64, ValidatedProtocol) -> Self
```

Note the argument order of `RunContext::new`: environment, sink, seed,
protocol. The seed is passed unchanged to the fixture through
`GenerationContext.seed`, is mixed into the block order (see
`balanced_order`), and is recorded in `RunSummary.seed` and the run id.

### `balanced_order`

`balanced_order` returns the cyclic rotation of implementation indices used for
one block.

```mbti
pub fn balanced_order(Int, Int) -> Array[Int]
```

`balanced_order(k, b)` is $[(0 + b) \bmod k, (1 + b) \bmod k, \dots, (k-1+b) \bmod k]$.
Under `OrderPolicy::BalancedBlocks(order_seed)` the runner uses block offset
$b + o$ with $o = (\text{order\_seed} \oplus \text{run\_seed}) \bmod k$; under
`FixedOrder` it uses the identity. Over any $k$ consecutive blocks every
implementation occupies every position exactly once.

```moonbit
test "rotated block order" {
  debug_inspect(@runner.balanced_order(3, 0), content="[0, 1, 2]")
  debug_inspect(@runner.balanced_order(3, 1), content="[1, 2, 0]")
  debug_inspect(@runner.balanced_order(3, 5), content="[2, 0, 1]")
}
```

## Protocols

### `ValidatedProtocol`

`ValidatedProtocol` is a `RunProtocol` that passed `validate_protocol`.

```mbti
pub struct ValidatedProtocol {
  protocol : @model.RunProtocol
}
```

It can only be obtained from `validate_protocol` or a `ProtocolPreset`, so a
plan never runs with a negative sample count or an empty iteration range.

### `validate_protocol`

`validate_protocol` checks a protocol and returns either a `ValidatedProtocol`
or every violation found.

```mbti
pub fn validate_protocol(@model.RunProtocol) -> Result[ValidatedProtocol, Array[ProtocolConfigError]]
```

| Rule | Error |
| --- | --- |
| `warmup_iterations >= 0` | `InvalidInteger("warmup_iterations", n)` |
| `warmup_time_us`, when set, finite and `>= 0` | `InvalidDuration("warmup_time_us", t)` |
| `exploratory_samples >= 0` | `InvalidInteger("exploratory_samples", n)` |
| `confirmatory_samples > 0` | `InvalidInteger("confirmatory_samples", n)` |
| `target_batch_time_us` finite and `> 0` | `InvalidDuration("target_batch_time_us", t)` |
| `max_sample_time_us` finite and `> 0` | `InvalidDuration("max_sample_time_us", t)` |
| `target_batch_time_us <= max_sample_time_us` | `InvalidDuration("target_batch_time_us", t)` |
| `0 < min_batch_iterations <= max_batch_iterations` | `InvalidIterationRange(min, max)` |
| `practical_delta_pct` finite and `>= 0` | `InvalidPracticalDelta(pct)` |
| `repeats_per_dataset >= 1` | `InvalidInteger("repeats_per_dataset", r)` |
| under `HierarchicalDatasetsAndRepeats`, $r$ divides `exploratory_samples` | `IndivisibleSamples("exploratory_samples", n, r)` |
| under `HierarchicalDatasetsAndRepeats`, $r$ divides `confirmatory_samples` | `IndivisibleSamples("confirmatory_samples", n, r)` |
| under the other designs, `repeats_per_dataset == 1` | `UnusedRepeatsPerDataset(r)` |

All rules are checked; the errors are returned together, in this order. The
divisibility rules are checked only when `repeats_per_dataset >= 1`. They make
every dataset of a hierarchical design belong to exactly one phase: with $r$
dividing $E$, blocks $0, \dots, E-1$ fill whole datasets, so no dataset is
measured partly by exploratory and partly by confirmatory blocks.

"Finite" excludes `NaN` and both infinities. Without that requirement a `NaN`
would pass every rule, because every comparison with `NaN` is false: a `NaN`
`target_batch_time_us` would disable calibration and a `NaN`
`practical_delta_pct` would make every later comparison meaningless. A
threshold of `0.0` is valid; `stats.compare_paired` then reports every
non-zero relative delta as `Faster` or `Slower` and an exact tie as
`Equivalent`.

```moonbit
test "protocol validation reports every problem" {
  let protocol = @model.RunProtocol::new(
    @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
    -1,
    None,
    @model.CalibrationProtocol::new(1000.0, 10, 5, 10000.0, @model.BatchPolicy::PerImplementation),
    1.0,
    @model.OrderPolicy::BalancedBlocks(7UL),
    @model.OutlierPolicy::ReportOnly,
    @model.ValidationCoverage::EveryDataset,
    2,
    0,
  )
  guard @runner.validate_protocol(protocol) is Err(errors) else { fail("expected errors") }
  inspect(errors.length(), content="3")
  inspect(errors[0] is InvalidInteger("warmup_iterations", -1), content="true")
  inspect(errors[1] is InvalidInteger("confirmatory_samples", 0), content="true")
  inspect(errors[2] is InvalidIterationRange(10, 5), content="true")
}

test "repeats per dataset must fit the design" {
  let hierarchical = @model.RunProtocol::new(
    @model.ExperimentDesign::HierarchicalDatasetsAndRepeats,
    1,
    None,
    @model.CalibrationProtocol::new(1000.0, 1, 1000, 100000.0, @model.BatchPolicy::PerImplementation),
    1.0,
    @model.OrderPolicy::BalancedBlocks(1UL),
    @model.OutlierPolicy::ReportOnly,
    @model.ValidationCoverage::EveryDataset,
    3,
    10,
    repeats_per_dataset=2,
  )
  guard @runner.validate_protocol(hierarchical) is Err(errors) else { fail("expected errors") }
  inspect(errors is [IndivisibleSamples("exploratory_samples", 3, 2)], content="true")
}
```

### `ProtocolConfigError`

`ProtocolConfigError` names one violated protocol rule.

```mbti
pub(all) enum ProtocolConfigError {
  InvalidInteger(String, Int)
  InvalidDuration(String, Double)
  InvalidIterationRange(Int, Int)
  InvalidPracticalDelta(Double)
  IndivisibleSamples(String, Int, Int)
  UnusedRepeatsPerDataset(Int)
}
```

The `String` payload is the field name; the number is the rejected value.
`IndivisibleSamples(field, samples, repeats)` carries the sample count and the
`repeats_per_dataset` that does not divide it; `UnusedRepeatsPerDataset(r)`
carries a `repeats_per_dataset` other than `1` under a design that does not
use it.

### `ProtocolPreset`

`ProtocolPreset` names a ready-made protocol.

```mbti
pub(all) enum ProtocolPreset {
  QuickCheck
  Development
  RegressionGate
  Custom(ValidatedProtocol)
}
pub fn ProtocolPreset::validated(Self) -> ValidatedProtocol
```

`validated` returns the preset's protocol (for `Custom`, the wrapped one). The
presets are:

| Field | `QuickCheck` | `Development` | `RegressionGate` |
| --- | --- | --- | --- |
| `experiment_design` | `FixedDatasetRepeatedMeasurements` | `FixedDatasetRepeatedMeasurements` | `HierarchicalDatasetsAndRepeats` |
| `warmup_iterations` | 1 | 3 | 10 |
| `warmup_time_us` | `None` | `Some(5000.0)` | `Some(10000.0)` |
| `target_batch_time_us` | 1000 | 5000 | 10000 |
| batch iterations | 1 to 1000 | 1 to 10000 | 5 to 10000 |
| `max_sample_time_us` | 100000 | 250000 | 1000000 |
| `batch_policy` | `PerImplementation` | `PerImplementation` | `PerImplementation` |
| `practical_delta_pct` | 1.0 | 1.0 | 0.5 |
| `order_policy` | `BalancedBlocks(1)` | `BalancedBlocks(1)` | `BalancedBlocks(1)` |
| `outlier_policy` | `ReportOnly` | `ReportOnly` | `TukeyFence` |
| `validation_coverage` | `ConfirmatoryOnly` | `EveryDataset` | `EveryMeasurement` |
| `exploratory_samples` | 1 | 3 | 5 |
| `confirmatory_samples` | 3 | 10 | 20 |
| `repeats_per_dataset` | 1 | 1 | 5 |
| datasets per scale | 1 | 1 | 5 (1 exploratory, 4 confirmatory) |

The runner acts on every field except `outlier_policy` and
`practical_delta_pct`, which are analysis settings: they are recorded in the
summary, and `report.document_from_jsonl` applies them when it compares
implementations. `RegressionGate` measures five datasets per scale, five
consecutive blocks each, and validates every measured batch; its first
dataset is measured only by the exploratory blocks.

## Implementations

### `Implementation`

`Implementation` is one competitor in a benchmark.

```mbti
pub struct Implementation[Prepared, Output, Context] {
  id : String
  version : String
  initial_context : () -> Context
  execution : ExecutionMode[Prepared, Output, Context]
  synchronize : () -> Unit
}
```

`id` names it in events and must be unique and non-empty within a case;
`version` is copied into every observation and validation. `initial_context`
starts each validation sequence and each measured batch. `synchronize` is
called immediately before the clock starts and after it stops; use it to wait
for queued asynchronous work (a GPU stream, a thread pool).

### `Implementation::stateless`

`Implementation::stateless` wraps a function of the prepared input that needs
no context.

```mbti
pub fn[Prepared, Output] Implementation::stateless(String, String, (Prepared) -> @model.OperationResult[Output, Unit]) -> Self[Prepared, Output, Unit]
```

The `next_context` of the function's result is ignored and replaced by
`Some(())`, so a stateless operation never ends a sequence early.

### `Implementation::in_process`

`Implementation::in_process` builds an implementation that runs in the current
process and threads a context.

```mbti
pub fn[Prepared, Output, Context] Implementation::in_process(String, String, () -> Context, (Prepared, Context) -> @model.OperationResult[Output, Context], synchronize? : () -> Unit) -> Self[Prepared, Output, Context]
```

Return `next_context = Some(c)` to continue with `c`; return `None` to end the
sequence (in a timed batch this marks the observation invalid).

```moonbit
test "a stateful implementation" {
  let counter = @runner.Implementation::in_process("counter", "1", () => 0, (step : Int, total : Int) => {
    @model.OperationResult::completed(total + step, total + step)
  })
  inspect(counter.id, content="counter")
  inspect((counter.initial_context)(), content="0")
}
```

### `Implementation::worker`

`Implementation::worker` builds an implementation that runs each operation in a
separate process.

```mbti
pub fn[Prepared, Output, Context] Implementation::worker(String, String, () -> Context, WorkerSpec[Prepared, Output, Context], synchronize? : () -> Unit) -> Self[Prepared, Output, Context]
```

Use it for code that may crash, hang or corrupt memory. A crash becomes an
`Aborted` outcome instead of ending the benchmark.

### `ExecutionMode`

`ExecutionMode` says where an operation runs.

```mbti
pub enum ExecutionMode[Prepared, Output, Context] {
  InProcess((Prepared, Context) -> @model.OperationResult[Output, Context])
  Subprocess(WorkerSpec[Prepared, Output, Context])
}
```

It is readonly outside the package; build it through the `Implementation`
constructors.

### `WorkerSpec`

`WorkerSpec` describes how to run one operation as a subprocess.

```mbti
pub struct WorkerSpec[Prepared, Output, Context] {
  command : String
  build_arguments : (Prepared, Context) -> Array[String]
  decode : (String) -> @model.OperationResult[Output, Context]
  timeout_ms : Int
  cwd : String?
}
pub fn[Prepared, Output, Context] WorkerSpec::new(String, (Prepared, Context) -> Array[String], (String) -> @model.OperationResult[Output, Context], timeout_ms? : Int, cwd? : String) -> Self[Prepared, Output, Context]
```

`build_arguments` produces the argument vector, `decode` turns the worker's
stdout into a result, `timeout_ms` defaults to `5000`, and `cwd` defaults to
the current directory.

```moonbit
fn echo_worker() -> @runner.Implementation[Int, String, Unit] {
  @runner.Implementation::worker(
    "echo",
    "1",
    () => (),
    @runner.WorkerSpec::new(
      "sh",
      (n, _) => ["-c", "echo " + n.to_string()],
      stdout => @model.OperationResult::completed(stdout.trim().to_owned(), ()),
      timeout_ms=1000,
    ),
  )
}

test "a worker is described, not started" {
  inspect(echo_worker().id, content="echo")
}
```

### `execute_operation`

`execute_operation` runs one operation of an implementation.

```mbti
pub async fn[Prepared, Output, Context] execute_operation(Implementation[Prepared, Output, Context], Prepared, Context) -> @model.OperationResult[Output, Context]
```

For `InProcess` it calls the function. For `Subprocess` it starts the command,
captures stdout and stderr, and maps the result:

| Worker result | Outcome |
| --- | --- |
| exit code 0 | the outcome and context returned by `decode(stdout)`, with stdout, stderr and exit code attached |
| exit code $\ne 0$ | `Aborted(code, stderr)`, no next context |
| no exit within `timeout_ms` | `Timeout(timeout_ms, "worker exceeded timeout")`; the process is killed |
| the process could not be started | `ParseFailure(error text)` |
| not on the native target | `Aborted(-1, "subprocess workers require the native target")` |

### `OutputSink`

`OutputSink` folds the outputs of a batch so that the compiler cannot discard
the work.

```mbti
pub struct OutputSink[Output, State, SinkValue] {
  initial : () -> State
  fold : (State, Output) -> State
  finish : (State) -> SinkValue
}
pub fn[Output, State, SinkValue] OutputSink::new(() -> State, (State, Output) -> State, (State) -> SinkValue) -> Self[Output, State, SinkValue]
pub fn[Output] OutputSink::keep_last() -> Self[Output, Output?, Output?]
```

`fold` runs inside the timed region after every operation; `finish` runs after
the clock stops and its value is passed to `@bench.Bench::keep`. `keep_last`
keeps the last output. Use `OutputSink::new` with a cheap checksum when the
output must be consumed:

```moonbit
test "a checksum sink" {
  let sink : @runner.OutputSink[Int, Int, Int] = @runner.OutputSink::new(
    () => 0,
    (state, output) => state ^ output,
    state => state,
  )
  let folded = [3, 5, 6].fold(init=(sink.initial)(), (state, x) => (sink.fold)(state, x))
  inspect((sink.finish)(folded), content="0")
}
```

## Describing a case

### `single_step`

`single_step` starts the short builder for a case with one operation per
input.

```mbti
pub fn[Scale] single_step(String, Array[Scale]) -> SingleStepCase[Scale]
```

The builder chain is `single_step(id, scales)`
`.with_immutable_input(generate, fingerprint)` `.compare(implementations)`
`.against_equal(reference, comparator)` `.compile()`. Each step copies the
arrays it receives.

### `Case`

`Case` is a namespace for the builder entry point.

```mbti
pub(all) enum Case {
  Case
}
pub fn[Scale] Case::single_step(String, Array[Scale]) -> SingleStepCase[Scale]
```

`Case::single_step(id, scales)` is the same as `single_step(id, scales)`.

### `SingleStepCase`

`SingleStepCase` is a case with an id and scales but no input yet.

```mbti
pub struct SingleStepCase[Scale] {
  id : String
  scales : Array[Scale]
}
pub fn[Scale] SingleStepCase::compile(Self[Scale]) -> Result[Unit, Array[BenchConfigError]]
pub fn[Scale, Input] SingleStepCase::with_immutable_input(Self[Scale], (@model.GenerationContext[Scale]) -> Input, (Input) -> String) -> ImmutableSingleStepCase[Scale, Input]
```

`compile` always fails at this stage and lists what is missing
(`MissingFixture`, `EmptyImplementations`, `MissingOracle`,
`MissingOutputSink`, plus `EmptyCaseId` and `EmptyScales` when they apply).
`with_immutable_input` adds an immutable fixture named `id + "-fixture"`,
version `"1"`, built with `@fixture.Fixture::immutable`.

### `ImmutableSingleStepCase`

`ImmutableSingleStepCase` is a case with an immutable input.

```mbti
pub struct ImmutableSingleStepCase[Scale, Input] {
  id : String
  scales : Array[Scale]
  fixture : @fixture.Fixture[Scale, Input, Input]
}
pub fn[Scale, Input, Output] ImmutableSingleStepCase::compare(Self[Scale, Input], Array[Implementation[Input, Output, Unit]]) -> ComparedSingleStepCase[Scale, Input, Output]
```

`compare` adds the stateless implementations to compare.

### `ComparedSingleStepCase`

`ComparedSingleStepCase` is a case with input and implementations.

```mbti
pub struct ComparedSingleStepCase[Scale, Input, Output] {
  id : String
  scales : Array[Scale]
  fixture : @fixture.Fixture[Scale, Input, Input]
  implementations : Array[Implementation[Input, Output, Unit]]
}
pub fn[Scale, Input, Expected, Output] ComparedSingleStepCase::against_equal(Self[Scale, Input, Output], (Input) -> Expected, (Expected, Output) -> Bool) -> BenchSpec[Scale, Input, Input, Expected, Output, Unit, Output?, Output?]
```

`against_equal(reference, comparator)` adds a reference oracle named
`id + "-reference"` built with `@experiment.ReferenceOracle::equal`, an
`OutputSink::keep_last` sink, a sequence length of 1, an empty scale text,
and placeholder texts for inputs and outputs (`"<input>"`, `"<output>"`). Its
replay spec has an empty command and the implementation id as the only
argument. With an empty scale text, validations carry `"scale":""` and
observations no `scale`, so the report places such runs by `dataset_id`. Use
`BenchSpec::advanced` when you need real text in events and replay artifacts,
in particular the scale.

### `BenchSpec`

`BenchSpec` is a complete, not yet validated case description.

```mbti
pub struct BenchSpec[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] {
  case : DifferentialCase[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue]
}
```

### `BenchSpec::advanced`

`BenchSpec::advanced` builds a case from all of its parts.

```mbti
pub fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] BenchSpec::advanced(String, @fixture.Fixture[Scale, Input, Prepared], Array[Implementation[Prepared, Output, Context]], OutputSink[Output, State, SinkValue], @experiment.OracleSpec[Input, Expected, Output, Context], Array[Scale], (Scale) -> String, Int, (Input, Int) -> @model.CaseDescriptor, (Input) -> String, (Output) -> String, (Context) -> String, (Input, String) -> @model.ReplaySpec, shrinker? : @experiment.Shrinker[Input]) -> Self[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue]
```

| Argument | Role |
| --- | --- |
| `id` | case id, copied into every event |
| `fixture` | materializes, clones, prepares and resets the input |
| `implementations` | the competitors (the array is copied) |
| `output_sink` | folds outputs inside timed batches |
| `oracle` | reference and/or relational validation |
| `scales` | one dataset per scale, in this order (copied) |
| `scale_text` | text of a scale in validation and observation events; the report's x axis |
| `sequence_length` | number of operations validated per implementation and dataset |
| `describe` | operation, operands, context and rounding of step $i$ for evidence |
| `input_text`, `output_text`, `context_text` | text forms used in evidence and failure artifacts |
| `replay` | the command that reproduces input and implementation id |
| `shrinker` | optional; minimizes failing inputs |

### `BenchSpec::with_sequence_length`

`with_sequence_length` returns a copy of the spec with another sequence length.

```mbti
pub fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] BenchSpec::with_sequence_length(Self[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue], Int) -> Self[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue]
```

### `BenchSpec::compile`

`compile` validates a spec and returns a plan or every configuration error.

```mbti
pub fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] BenchSpec::compile(Self[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue], protocol? : ValidatedProtocol) -> Result[ValidatedBenchPlan[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue], Array[BenchConfigError]]
```

It checks, in order: a non-empty case id, at least one scale, at least one
implementation, a positive sequence length, non-empty, unique implementation
ids, and that a fixture with `SetupFrequency::PerRun` serves a single
dataset. Without `protocol` every scale counts as one dataset, the fewest any
design materializes; with it, the datasets the protocol's design
materializes are counted. `run` repeats the setup check with the protocol of
its context, so a plan compiled without a protocol cannot run a `PerRun`
fixture over several datasets either.

```moonbit
test "compile collects every configuration error" {
  let anonymous = @runner.Implementation::stateless("", "1", (x : Int) => {
    @model.OperationResult::completed(x, ())
  })
  let result = @runner.single_step("", ([] : Array[Int]))
    .with_immutable_input(context => context.dataset_key.scale, x => x.to_string())
    .compare([anonymous])
    .against_equal(x => x, (expected, actual) => expected == actual)
    .compile()
  guard result is Err(errors) else { fail("expected errors") }
  inspect(errors.length(), content="3")
  inspect(errors[0] is EmptyCaseId, content="true")
  inspect(errors[1] is EmptyScales, content="true")
  inspect(errors[2] is EmptyImplementationId(0), content="true")
}
```

### `BenchConfigError`

`BenchConfigError` names one problem in a case description.

```mbti
pub(all) enum BenchConfigError {
  MissingFixture
  MissingOracle
  MissingOutputSink
  MissingSerializer(String)
  EmptyCaseId
  EmptyImplementations
  EmptyScales
  EmptyImplementationId(Int)
  DuplicateImplementationId(String)
  InvalidSequenceLength(Int)
  InvalidOracleSequenceLength(Int)
  OracleSequenceLengthMismatch(Int, Int)
  PerRunSetupWithMultipleDatasets(Int)
}
```

`EmptyImplementationId` carries the index of the implementation,
`DuplicateImplementationId` the repeated id, `InvalidSequenceLength` the
rejected case length. `InvalidOracleSequenceLength` carries a non-positive
length returned by a reference oracle; `OracleSequenceLengthMismatch` carries
the configured case length and the oracle length, in that order. 
`PerRunSetupWithMultipleDatasets` carries the number of datasets
of the run. A `PerRun` setup prepares one value for the whole run, but a
prepared value is derived from one dataset's input, so it cannot serve several
datasets; use `PerDataset` instead. The `Missing*` constructors come from
`SingleStepCase::compile`; `MissingSerializer` is reserved and not produced by
the current code.

### `RunConfigError`

`RunConfigError` is raised by `run` when the plan and the protocol of the run
context are incompatible.

```mbti
pub(all) suberror RunConfigError {
  RunConfigError(Array[BenchConfigError])
}
```

The payload lists the problems, currently `PerRunSetupWithMultipleDatasets`.
`run` raises it before it emits any event.

```moonbit
fn per_run_spec(scales : Array[Int]) -> @runner.BenchSpec[Int, Int, Int, Int, Int, Unit, Int?, Int?] {
  let fixture = @fixture.Fixture::new(
    "shared",
    "1",
    (context : @model.GenerationContext[Int]) => context.dataset_key.scale,
    x => x.to_string(),
    x => x,
    (x, _, _) => x,
    (_, _) => (),
    @model.SetupPolicy::new(PerRun, ExcludedFromMeasurement, RunWorkspace),
  )
  @runner.BenchSpec::advanced(
    "per-run",
    fixture,
    [@runner.Implementation::stateless("id", "1", x => @model.OperationResult::completed(x, ()))],
    @runner.OutputSink::keep_last(),
    @experiment.OracleSpec::Reference(@experiment.ReferenceOracle::equal("id", x => x, (e, a) => e == a)),
    scales,
    n => n.to_string(),
    1,
    (x, _) => @model.CaseDescriptor::new("id", [x.to_string()], "", ""),
    x => x.to_string(),
    x => x.to_string(),
    _ => "",
    (x, id) => @model.ReplaySpec::new("", [id, x.to_string()]),
  )
}

async test "a per-run setup serves one dataset" {
  let two_scales = per_run_spec([1, 2]).compile()
  inspect(two_scales is Err([PerRunSetupWithMultipleDatasets(2)]), content="true")
  let gate = @runner.ProtocolPreset::RegressionGate.validated()
  let one_scale = per_run_spec([1]).compile(protocol=gate)
  inspect(one_scale is Err([PerRunSetupWithMultipleDatasets(5)]), content="true")
  let plan = per_run_spec([1]).compile().unwrap()
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(@model.ExecutionTarget::Native, "moonc 0.10", "", "i32"),
    @model.PerformanceEnvironment::new("native", "laptop", "rc", 1, "monotonic"),
    @model.ProvenanceEnvironment::new("macos", "host", "2026-10-08T00:00:00Z", "HEAD", "run-2"),
  )
  let raised = try {
    ignore(@runner.run(plan, @runner.RunContext::new(environment, @event.InMemorySink::new().as_sink(), 1UL, gate)))
    false
  } catch {
    @runner.RunConfigError(_) => true
    _ => false
  }
  inspect(raised, content="true")
}
```

### `DifferentialCase`

`DifferentialCase` is the record behind a spec or a plan.

```mbti
pub struct DifferentialCase[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] {
  id : String
  fixture : @fixture.Fixture[Scale, Input, Prepared]
  implementations : Array[Implementation[Prepared, Output, Context]]
  output_sink : OutputSink[Output, State, SinkValue]
  oracle : @experiment.OracleSpec[Input, Expected, Output, Context]
  scales : Array[Scale]
  scale_text : (Scale) -> String
  sequence_length : Int
  describe : (Input, Int) -> @model.CaseDescriptor
  input_text : (Input) -> String
  output_text : (Output) -> String
  context_text : (Context) -> String
  shrinker : @experiment.Shrinker[Input]?
  replay : (Input, String) -> @model.ReplaySpec
}
```

Its fields mirror the arguments of `BenchSpec::advanced`.

### `ValidatedBenchPlan`

`ValidatedBenchPlan` is a case that passed `BenchSpec::compile`.

```mbti
pub struct ValidatedBenchPlan[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] {
  case : DifferentialCase[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue]
}
```

It can only be created by `compile`, and `run` accepts nothing else.
