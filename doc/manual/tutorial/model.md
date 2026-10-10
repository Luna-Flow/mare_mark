# model tutorial

This tutorial shows how to describe a benchmark run with the shared types:
an environment snapshot you can compare across runs, a protocol you can
record, outcomes that say why an operation has no value, and a deployment
policy derived from results. Every example is a complete test.

| I want to | Use |
| --- | --- |
| describe the machine a run used | `@model.EnvironmentSnapshot::new`, or `@env_detect.detect` to fill it in |
| know whether two runs may be compared | `@model.environment_compatible` |
| write down how a run was measured | `@model.RunProtocol::new` and `@model.protocol_identity` |
| give every run its own id | `@model.run_identity` (the runner calls it) |
| say why an operation has no value | the cases of `@model.ExecutionOutcome` |
| turn a crossover into a deployment rule | `@model.CrossoverResult` and `@model.DeploymentPolicy` |

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.4.0
```

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/runner",
}
```

`runner` is needed only for the protocol presets in the run id example.

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
toolchain and flags do. Writing the snapshot by hand is the right choice for a
test or for a machine you are describing from elsewhere; for the machine the
benchmark runs on, `@env_detect.detect` fills in the same three parts (see the
[env_detect tutorial](env_detect.md)).

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
  inspect(@model.protocol_identity(protocol), content="mmkp_2:ee0e3d65a8dfe6b6")
  let reseeded = @model.RunProtocol::new(
    protocol.experiment_design,
    protocol.warmup_iterations,
    protocol.warmup_time_us,
    protocol.calibration,
    protocol.practical_delta_pct,
    @model.OrderPolicy::BalancedBlocks(2UL),
    protocol.outlier_policy,
    protocol.validation_coverage,
    protocol.exploratory_samples,
    protocol.confirmatory_samples,
  )
  inspect(@model.protocol_identity(reseeded) == @model.protocol_identity(protocol), content="false")
}
```

The identity is a 64-bit digest of every protocol field, so changing any of
them, here only the seed of the block order, gives another key. It is a key,
not a record: the runner also stores the whole protocol in the JSONL summary,
where `@event.protocol_from_json` reads it back.

### Give every run its own id

The runner names a run with `run_identity`: the case, the protocol identity,
the seed, and the provenance run id and timestamp of the environment.

```moonbit
test "run ids differ between runs" {
  let protocol = @runner.ProtocolPreset::QuickCheck.validated().protocol
  let monday = @model.ProvenanceEnvironment::new("linux", "ci-7", "2026-10-08T08:00:00Z", "a1b2c3", "nightly-101")
  let tuesday = @model.ProvenanceEnvironment::new("linux", "ci-7", "2026-10-09T08:00:00Z", "a1b2c3", "nightly-102")
  inspect(@model.run_identity("sum", protocol, 42UL, monday), content="sum|mmkp_2:a8272a0d9e84b872|42|nightly-101|2026-10-08T08:00:00Z")
  inspect(@model.run_identity("sum", protocol, 42UL, monday) == @model.run_identity("sum", protocol, 42UL, tuesday), content="false")
}
```

Keep the provenance run id unique, for example with
`@env_detect.new_run_id`, and the run ids of a long series of runs never
collide.

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
- **Reusing the provenance run id.** `RunSummary.run_id` contains it; runs
  with the same case, protocol, seed, provenance run id and timestamp share
  an id.
- **Comparing `mmkp_1` and `mmkp_2` keys.** Records written before the
  identity covered every field carry `mmkp_1:…` keys; they cannot be
  compared with the new ones. Compare the recorded protocols instead.
- **Expecting the runner to act on every protocol field.**
  `practical_delta_pct` and `outlier_policy` do not change what is measured;
  the report applies them when it compares implementations.

## Next steps

- [model API](../api/model.md) and [model design](../design/model.md).
- [runner tutorial](runner.md) to use these types in a run.
