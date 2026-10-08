# fixture tutorial

This tutorial shows how to hand benchmark inputs to implementations safely: an
immutable input shared by everyone, a mutable input copied before each batch,
an input prepared differently per implementation, and setup cost that is
deliberately included in the measurement. Every example is a complete test.

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```text
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/fixture",
}
```

```moonbit
test "an immutable input" {
  let fixture = @fixture.Fixture::immutable(
    "squares", "1", context => Array::makei(context.dataset_key.scale, i => i * i), (xs : Array[Int]) => xs.length().to_string(),
  )
  let context = @model.GenerationContext::new(7UL, "suite", "sum", @model.DatasetKey::new(4, 0), fixture.id, fixture.version)
  debug_inspect(@fixture.materialize(fixture, context), content="[0, 1, 4, 9]")
}
```

## Everyday tasks

### Copy a mutable input

An implementation that sorts in place must get a fresh copy each time:

```moonbit
test "clone before prepare" {
  let fixture : @fixture.Fixture[Int, Array[Int], Array[Int]] = @fixture.Fixture::new(
    "reversed", "1",
    context => Array::makei(context.dataset_key.scale, i => context.dataset_key.scale - i),
    xs => xs.length().to_string(),
    xs => xs.copy(),
    (xs, _, _) => xs,
    (_, _) => (),
    @model.SetupPolicy::new(@model.SetupFrequency::PerBatch, @model.SetupTiming::ExcludedFromMeasurement, @model.WorkspaceScope::BatchWorkspace),
  )
  let context = @model.GenerationContext::new(0UL, "s", "sort", @model.DatasetKey::new(3, 0), fixture.id, fixture.version)
  let input = @fixture.materialize(fixture, context)
  let prepared = @fixture.prepare(fixture, (fixture.clone_input)(input), "sort", @fixture.SampleContext::new(0, "sort", 0))
  prepared.sort()
  debug_inspect(prepared, content="[1, 2, 3]")
  debug_inspect(input, content="[3, 2, 1]")
}
```

The runner calls `clone_input` for you; the explicit call here shows what
happens.

### Prepare per implementation

`prepare` receives the implementation id. Give each implementation the layout
it expects:

```moonbit
test "layout per implementation" {
  let fixture : @fixture.Fixture[Int, Array[Int], Array[Int]] = @fixture.Fixture::new(
    "matrix-2x2", "1",
    _ => [1, 2, 3, 4],
    xs => xs.length().to_string(),
    xs => xs.copy(),
    (xs, implementation, _) => if implementation == "column-major" { [xs[0], xs[2], xs[1], xs[3]] } else { xs },
    (_, _) => (),
    @model.SetupPolicy::new(@model.SetupFrequency::PerImplementation, @model.SetupTiming::ExcludedFromMeasurement, @model.WorkspaceScope::ImplementationWorkspace),
  )
  let sample = @fixture.SampleContext::new(0, "column-major", 0)
  debug_inspect(@fixture.prepare(fixture, [1, 2, 3, 4], "column-major", sample), content="[1, 3, 2, 4]")
}
```

The transposition happens once per implementation and outside the clock.

### Include setup on purpose

To measure "allocate and compute" as one cost, prepare per iteration and
include it:

```moonbit
test "setup inside the measurement" {
  let policy = @model.SetupPolicy::new(
    @model.SetupFrequency::PerIteration,
    @model.SetupTiming::IncludedInMeasurement,
    @model.WorkspaceScope::OperationWorkspace,
  )
  let fixture : @fixture.Fixture[Int, Int, Array[Double]] = @fixture.Fixture::new(
    "fresh-buffer", "1",
    context => context.dataset_key.scale,
    n => n.to_string(),
    n => n,
    (n, _, _) => Array::make(n, 0.0),
    (_, _) => (),
    policy,
  )
  inspect(fixture.setup_policy.timing is IncludedInMeasurement, content="true")
}
```

Every observation then records `setup_timing` as `IncludedInMeasurement`, so a
reader knows the number contains the allocation.

## Going further

- Use the `sample_id` of `SampleContext` to tell validation (`-1`), warmup and
  calibration (other negative ids) from measured blocks; the
  [runner design](../design/runner.md) lists them.
- Derive random inputs from `context.seed` with `@generator.derive_seed`; see
  the [generator tutorial](generator.md).

## Common pitfalls

- **Identity `clone_input` with a mutating implementation.** Later batches
  see modified data.
- **Expensive `materialize` work assumed to be timed.** It never is.
- **Including per-batch setup.** The amortized cost then depends on the
  calibrated batch size.
- **Resetting by dropping a long-lived value.** The runner reuses it after
  reset.

## Next steps

- [fixture API](../api/fixture.md), [fixture design](../design/fixture.md).
- [runner tutorial](runner.md) to run cases with these fixtures.
