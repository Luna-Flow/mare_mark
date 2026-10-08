# model tutorial

This tutorial shows how to describe a benchmark run with the shared types:
an environment snapshot you can compare across runs, a protocol you can
record, outcomes that say why an operation has no value, and a deployment
policy derived from results. Every example is a complete test.

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```text
import {
  "Luna-Flow/mare_mark/model",
}
```

Describe the machine and check whether two runs may be compared:

```moonbit
test "describe two runs" {
  let semantic = @model.SemanticEnvironment::new(@model.ExecutionTarget::Native, "moonc 0.10.14", "release", "f64")
  let performance = @model.PerformanceEnvironment::new(
    "native", "AMD EPYC 7763", "default", 1, "monotonic", frequency_policy="performance",
  )
  let first = @model.EnvironmentSnapshot::new(
    semantic, performance,
    @model.ProvenanceEnvironment::new("linux", "ci-7", "2026-10-08T08:00:00Z", "a1b2c3", "nightly-101"),
  )
  let second = @model.EnvironmentSnapshot::new(
    semantic, performance,
    @model.ProvenanceEnvironment::new("linux", "ci-3", "2026-10-09T08:00:00Z", "d4e5f6", "nightly-102"),
  )
  inspect(@model.environment_compatible(first, second), content="true")
}
```

Different hosts, dates and revisions do not matter; the declared hardware,
toolchain and flags do.

## Everyday tasks

### Record the protocol with the results

```moonbit
test "a protocol and its identity" {
  let protocol = @model.RunProtocol::new(
    @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
    3,
    Some(5000.0),
    @model.CalibrationProtocol::new(5000.0, 1, 10000, 250000.0, @model.BatchPolicy::PerImplementation),
    1.0,
    @model.OrderPolicy::BalancedBlocks(1UL),
    @model.OutlierPolicy::ReportOnly,
    @model.ValidationCoverage::EveryDataset,
    3,
    10,
  )
  inspect(@model.protocol_identity(protocol), content="mmkp_1:3:10:1")
}
```

The identity is a short cache key. Store the whole protocol as well; the key
covers only the warmup count, the confirmatory sample count and the threshold.

### Return precise outcomes

An implementation that cannot handle an input says so instead of returning a
fake value:

```moonbit
fn checked_sqrt(x : Double) -> @model.OperationResult[Double, Unit] {
  if x < 0.0 {
    @model.OperationResult::new(Unsupported("negative input"), Some(()))
  } else {
    @model.OperationResult::completed(x.sqrt(), ())
  }
}

test "unsupported is not wrong" {
  let result = checked_sqrt(-4.0)
  inspect(result.outcome.kind(), content="unsupported")
  inspect(result.outcome.value_option() is None, content="true")
  inspect(checked_sqrt(9.0).outcome.value_option() == Some(3.0), content="true")
}
```

The runner counts `Unsupported` separately from failures, and the report lists
it in the capability matrix.

### Turn a crossover into a deployment policy

```moonbit
test "piecewise deployment" {
  let crossover : @model.CrossoverResult[Int] = @model.CrossoverResult::found(
    @model.ScaleBoundary::new(64, 128), "piecewise-confirmed", ["A", "A", "B"],
  )
  guard crossover is Found(boundary, _, evidence) else { fail("no crossover") }
  let policy : @model.DeploymentPolicy[Int, String] = Piecewise([
    @model.Region::new(None, Some(boundary.below), "scalar", evidence),
    @model.Region::new(Some(boundary.at_or_above), None, "blocked", evidence),
  ])
  guard policy is Piecewise(regions) else { fail("not piecewise") }
  inspect(regions.length(), content="2")
}
```

## Going further

- Build `Observation`, `Validation` and `RunSummary` values by hand to test
  your own sinks; the [event tutorial](event.md) does this.
- Use `ExpectedDifference` for documented deviations (for example a library
  that rounds differently by design), so they are counted, not hidden.
- Check `ArtifactVersion::V1.identifier()` before reading foreign JSONL.

## Common pitfalls

- **Describing the environment vaguely.** `"cpu"` matches every other
  `"cpu"`; write the model and the frequency policy.
- **Putting the run id only in `RunSummary`.** The runner's `run_id` is not
  unique; use `ProvenanceEnvironment.run_id`.
- **Expecting the runner to act on every protocol field.** It does not act on
  `experiment_design`, `outlier_policy` or `validation_coverage`.

## Next steps

- [model API](../api/model.md) and [model design](../design/model.md).
- [runner tutorial](runner.md) to use these types in a run.
