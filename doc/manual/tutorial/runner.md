# runner tutorial

This tutorial builds benchmark cases of increasing realism: a single
comparison, a JSONL event stream, a mutable input with an explicit lifecycle, a
stateful operation sequence, a wrong implementation caught and minimized
before it is timed, and a protocol of your own. Every example is a complete
`async test`; the outputs shown are the parts that do not depend on the speed
of your machine.

| I want to | Use |
| --- | --- |
| compare implementations on the same input | `@runner.Case::single_step(...).with_immutable_input(...).compare(...)` |
| validate against a reference first | `.against_equal(...)` or a full oracle with `BenchSpec::advanced` |
| keep the raw record | an `@event.JsonlSink` in the `RunContext` |
| give a mutable input a lifecycle | a `@fixture.Fixture` with `prepare` and `reset` |
| measure a stateful operation sequence | `Implementation::in_process` with a `Context` |
| choose how carefully to measure | `@runner.ProtocolPreset` or `@runner.validate_protocol` |
| isolate a payload that may crash | `Implementation::worker` (native) |

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/runner",
  "moonbitlang/async",
  "Luna-Flow/mare_mark/fixture",
  "Luna-Flow/mare_mark/experiment",
}
```

A run needs an environment snapshot. Describe the machine once:

```moonbit
fn laptop() -> @model.EnvironmentSnapshot {
  @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(@model.ExecutionTarget::Native, "moonc 0.10", "release", "f64"),
    @model.PerformanceEnvironment::new("native", "apple-m2", "default", 1, "monotonic"),
    @model.ProvenanceEnvironment::new("macos", "laptop", "2026-10-08T09:00:00Z", "HEAD", "tutorial"),
  )
}
```

Then compare two ways of summing `0, 1, …, n-1`:

```moonbit
async test "quick start" {
  let looped = @runner.Implementation::stateless("loop", "1", (n : Int) => {
    let mut total = 0
    for i in 0..<n {
      total += i
    }
    @model.OperationResult::completed(total, ())
  })
  let closed = @runner.Implementation::stateless("formula", "1", (n : Int) => {
    @model.OperationResult::completed(n * (n - 1) / 2, ())
  })
  let plan = @runner.single_step("triangle", [100, 10000])
    .with_immutable_input(context => context.dataset_key.scale, n => n.to_string())
    .compare([looped, closed])
    .against_equal(n => n * (n - 1) / 2, (expected, actual) => expected == actual)
    .compile()
    .unwrap()
  let memory = @event.InMemorySink::new()
  let context = @runner.RunContext::new(
    laptop(), memory.as_sink(), 42UL, @runner.ProtocolPreset::QuickCheck.validated(),
  )
  let summary = @runner.run(plan, context)
  inspect(summary.passed_count, content="4")
  inspect(memory.observations.length(), content="16")
  inspect(memory.calibrations.length(), content="4")
}
```

Both implementations passed validation on both scales (four validations).
Each scale then got one calibration per implementation and four blocks
(`QuickCheck`: one exploratory, three confirmatory) of two batches each.
`memory.observations[i].raw_elapsed_us` holds the per-iteration times.

## Everyday tasks

### Keep the run as JSONL

The JSONL stream is the audit record of a run. Send events to a `JsonlSink`,
and to memory at the same time with `tee`:

```moonbit
async test "write JSONL and keep events in memory" {
  let id = @runner.Implementation::stateless("identity", "1", (x : Int) => {
    @model.OperationResult::completed(x, ())
  })
  let plan = @runner.single_step("identity", [1])
    .with_immutable_input(context => context.dataset_key.scale, x => x.to_string())
    .compare([id])
    .against_equal(x => x, (expected, actual) => expected == actual)
    .compile()
    .unwrap()
  let jsonl = @event.JsonlSink::new()
  let memory = @event.InMemorySink::new()
  let sink = @event.tee(memory.as_sink(), jsonl.as_sink())
  let summary = @runner.run(
    plan,
    @runner.RunContext::new(laptop(), sink, 7UL, @runner.ProtocolPreset::QuickCheck.validated()),
  )
  inspect(summary.artifact_location.unwrap(), content="jsonl://memory/mmkp_1:1:3:1:identity")
  let lines = jsonl.to_jsonl().split("\n").to_array()
  inspect(lines.length(), content="7")
  inspect(lines[0].contains("\"type\":\"validation\""), content="true")
  inspect(lines[6].contains("\"type\":\"summary\""), content="true")
}
```

One validation, one calibration, four observations and the summary make seven
lines. Write `jsonl.to_jsonl()` to a file with your own IO, or stream lines as
they happen with `@event.streaming_jsonl`.

### Give a mutable input an explicit lifecycle

An in-place sort destroys its input. The fixture copies the generated array
before every batch (`PerBatch`) and keeps that copy outside the timed region
(`ExcludedFromMeasurement`):

```moonbit
async test "an in-place sort on a fresh copy per batch" {
  let fixture : @fixture.Fixture[Int, Array[Int], Array[Int]] = @fixture.Fixture::new(
    "descending",
    "1",
    context => Array::makei(context.dataset_key.scale, i => context.dataset_key.scale - i),
    input => "len=" + input.length().to_string(),
    input => input.copy(),
    (input, _, _) => input,
    (_, _) => (),
    @model.SetupPolicy::new(
      @model.SetupFrequency::PerBatch,
      @model.SetupTiming::ExcludedFromMeasurement,
      @model.WorkspaceScope::BatchWorkspace,
    ),
  )
  let sort_in_place = @runner.Implementation::stateless("sort", "1", (xs : Array[Int]) => {
    xs.sort()
    @model.OperationResult::completed(xs[0], ())
  })
  let oracle = @experiment.ReferenceOracle::equal(
    "minimum",
    (input : Array[Int]) => input.fold(init=input[0], (low, x) => if x < low { x } else { low }),
    (expected, actual) => expected == actual,
  )
  let spec = @runner.BenchSpec::advanced(
    "sort",
    fixture,
    [sort_in_place],
    @runner.OutputSink::keep_last(),
    @experiment.OracleSpec::Reference(oracle),
    [64, 4096],
    n => n.to_string(),
    1,
    (input, _) => @model.CaseDescriptor::new("sort", [input.length().to_string()], "", ""),
    input => "len=" + input.length().to_string(),
    first => first.to_string(),
    _ => "",
    (input, implementation) => @model.ReplaySpec::new("sort-worker", [implementation, input.length().to_string()]),
  )
  let memory = @event.InMemorySink::new()
  let summary = @runner.run(
    spec.compile().unwrap(),
    @runner.RunContext::new(laptop(), memory.as_sink(), 1UL, @runner.ProtocolPreset::QuickCheck.validated()),
  )
  inspect(summary.passed_count, content="2")
  inspect(memory.observations.all(o => o.valid), content="true")
}
```

Without `clone_input` the second batch would sort an already sorted array and
measure a different workload. To include the copy in the measurement, use
`IncludedInMeasurement`; to copy before every single operation, use
`PerIteration`. The [runner design](../design/runner.md) lists exactly what
each combination puts inside the clock.

### Validate a stateful sequence

Operations that carry state, such as a running total, are validated as a
sequence. The implementation and the reference oracle each thread their own
context, and `sequence_length` sets how many steps are compared:

```moonbit
async test "a running total validated over five steps" {
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::immutable(
    "step",
    "1",
    context => context.dataset_key.scale,
    x => x.to_string(),
  )
  let running = @runner.Implementation::in_process("running", "1", () => 0, (step : Int, total : Int) => {
    @model.OperationResult::completed(total + step, total + step)
  })
  let reference = @experiment.ReferenceOracle::new(
    "running-total",
    () => 0,
    _ => 5,
    (step : Int, index, total : Int) => {
      ignore(index)
      @model.OperationResult::completed(total + step, total + step)
    },
    (_, _, expected, actual) => {
      match (expected, actual) {
        (Value(e), Value(a)) if e == a => @model.ValidationStatus::Valid
        _ => @model.ValidationStatus::Invalid("total differs")
      }
    },
    total => total.to_string(),
  )
  let spec = @runner.BenchSpec::advanced(
    "running-total",
    fixture,
    [running],
    @runner.OutputSink::new(() => 0, (sum, x) => sum + x, sum => sum),
    @experiment.OracleSpec::Reference(reference),
    [3],
    n => n.to_string(),
    5,
    (step, index) => @model.CaseDescriptor::new("add", [step.to_string(), index.to_string()], "total", ""),
    x => x.to_string(),
    x => x.to_string(),
    total => total.to_string(),
    (step, implementation) => @model.ReplaySpec::new("total-worker", [implementation, step.to_string()]),
  )
  let memory = @event.InMemorySink::new()
  let summary = @runner.run(
    spec.compile().unwrap(),
    @runner.RunContext::new(laptop(), memory.as_sink(), 3UL, @runner.ProtocolPreset::QuickCheck.validated()),
  )
  inspect(summary.validation_count, content="5")
  inspect(summary.passed_count, content="5")
  guard memory.validations[4].evidence is Some(evidence) else { fail("no evidence") }
  inspect(evidence.actual, content="15")
  inspect(evidence.context, content="15")
}
```

Step 4 of the sequence returns $3 \cdot 5 = 15$, and the evidence records both
the value and the context after the step.

### Catch and minimize a wrong implementation

An off-by-one implementation fails validation. With a shrinker, the runner
reduces the failing input before writing the failure artifact:

```moonbit
async test "a failing implementation is minimized" {
  let off_by_one = @runner.Implementation::stateless("off-by-one", "0.1", (x : Int) => {
    @model.OperationResult::completed(x + 1, ())
  })
  let spec = @runner.BenchSpec::advanced(
    "identity",
    @fixture.Fixture::immutable("ints", "1", context => context.dataset_key.scale, (x : Int) => x.to_string()),
    [off_by_one],
    @runner.OutputSink::keep_last(),
    @experiment.OracleSpec::Reference(
      @experiment.ReferenceOracle::equal("identity", x => x, (expected, actual) => expected == actual),
    ),
    [40],
    n => n.to_string(),
    1,
    (x, _) => @model.CaseDescriptor::new("identity", [x.to_string()], "", ""),
    x => x.to_string(),
    x => x.to_string(),
    _ => "",
    (x, implementation) => @model.ReplaySpec::new("identity-worker", [implementation, x.to_string()]),
    shrinker=@experiment.Shrinker::new(x => if x > 0 { [x / 2] } else { [] }, x => x.to_string()),
  )
  let memory = @event.InMemorySink::new()
  let summary = @runner.run(
    spec.compile().unwrap(),
    @runner.RunContext::new(laptop(), memory.as_sink(), 9UL, @runner.ProtocolPreset::QuickCheck.validated()),
  )
  inspect(summary.failed_count, content="1")
  let failure = memory.failures[0]
  inspect(failure.minimal_input, content="0")
  debug_inspect(failure.shrink_path, content="[\"20\", \"10\", \"5\", \"2\", \"1\", \"0\"]")
}
```

The failure event carries the seed, the original and minimal fingerprints, the
shrink path and the replay command `identity-worker off-by-one 40`. The
implementation is still timed; the report hides its series and shows the
mismatch instead.

### Write your own protocol

Presets cover common cases. For a gate in CI you may want more confirmatory
blocks, a multiple of the number of implementations so that every rotation
cycle is complete:

```moonbit
test "a custom protocol" {
  let protocol = @model.RunProtocol::new(
    @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
    5,
    Some(20000.0),
    @model.CalibrationProtocol::new(2000.0, 4, 100000, 200000.0, @model.BatchPolicy::PerImplementation),
    2.0,
    @model.OrderPolicy::BalancedBlocks(2026UL),
    @model.OutlierPolicy::ReportOnly,
    @model.ValidationCoverage::EveryDataset,
    2,
    30,
  )
  let validated = @runner.validate_protocol(protocol).unwrap()
  let preset = @runner.ProtocolPreset::Custom(validated)
  inspect(preset.validated().protocol.confirmatory_samples, content="30")
  inspect(@model.protocol_identity(protocol), content="mmkp_1:5:30:2")
}
```

With two implementations, $2 + 30 = 32$ blocks form 16 complete cycles.

## Going further

**Isolate unsafe code.** `Implementation::worker` runs each operation in a
child process with a timeout; a crash becomes an `Aborted` outcome and a hang
a `Timeout`, both counted as infrastructure failures. Workers need the native
target. See [`WorkerSpec`](../api/runner.md#workerspec).

**Asynchronous devices.** Pass `synchronize=` to `Implementation::in_process`
with a function that blocks until queued work is done. The runner calls it
right before starting and right before stopping the clock.

**Equal work per batch.** `BatchPolicy::SharedBatchSize` gives every
implementation the smallest calibrated batch size.

**Several implementations against each other.** Use
`OracleSpec::Relational` or `ReferenceAndRelational` to compare
implementations pairwise when no single reference exists; see the
[experiment tutorial](experiment.md).

**Reproducible inputs.** Derive dataset seeds inside the fixture with
`@generator.derive_seed(context.seed, context.case_id, context.dataset_key.dataset_id)`;
see the [generator tutorial](generator.md).

## Common pitfalls

- **Work inside the payload that is not the payload.** Allocation, parsing or
  printing inside the implementation function is timed. Move it into the
  fixture.
- **Forgetting `clone_input` for mutating code.** Later batches then measure a
  different input.
- **Reading timings from invalid observations.** Filter on `valid` and drop
  datasets with validation failures before comparing.
- **Mixing phases.** Exploratory blocks are for orientation; decide on
  confirmatory ones.
- **Assuming `run_id` is unique.** It identifies protocol and case; put a
  unique id in `ProvenanceEnvironment.run_id`.
- **Calling `run` outside an async context.** It is an `async fn`.
- **A zero threshold with noisy data.** `validate_protocol` accepts `0.0`, and
  `stats.compare_paired` then calls every non-zero difference `Faster` or
  `Slower`. Choose the smallest change you care about.

## Next steps

- [runner API](../api/runner.md) and [runner design](../design/runner.md).
- [stats tutorial](stats.md) to turn observations into a decision.
- [report tutorial](report.md) to publish the JSONL as HTML.
- [fixture tutorial](fixture.md) and [experiment tutorial](experiment.md) for
  lifecycles and oracles.
