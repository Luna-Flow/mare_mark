# fixture API

## Purpose

`Luna-Flow/mare_mark/fixture` describes the lifecycle of a benchmark input:
how it is generated for a dataset, fingerprinted, copied, prepared for an
implementation and reset afterwards, and whether that work is timed. The runner
calls these functions; the [fixture design](../design/fixture.md) explains the
lifecycle.

Source: [`src/fixture/fixture.mbt`](../../../src/fixture/fixture.mbt).

## Importing

Add the packages to the `moon.pkg` of the package that uses them:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/fixture",
}
```

The examples on this page call them through their default aliases (`@model`,
`@fixture`).

## Fixtures

### `Fixture`

`Fixture` is the lifecycle of one kind of input.

```mbti
pub struct Fixture[Scale, Input, Prepared] {
  id : String
  version : String
  materialize : (@model.GenerationContext[Scale]) -> Input
  fingerprint : (Input) -> String
  clone_input : (Input) -> Input
  prepare : (Input, String, SampleContext) -> Prepared
  reset : (Prepared, ResetContext) -> Unit
  setup_policy : @model.SetupPolicy
}
```

| Field | Called | Purpose |
| --- | --- | --- |
| `materialize` | once per dataset | generate the input from the context |
| `fingerprint` | once per dataset, and for minimized inputs | identify the input in events |
| `clone_input` | before every `prepare` | protect the materialized input from mutation |
| `prepare` | per the setup policy | turn a copy into what an implementation runs on; receives the implementation id |
| `reset` | after the prepared value is used | release or restore it |
| `setup_policy` | | how often `prepare` runs and whether it is timed |

### `Fixture::new`

`Fixture::new` builds a fixture from all of its parts.

```mbti
pub fn[Scale, Input, Prepared] Fixture::new(String, String, (@model.GenerationContext[Scale]) -> Input, (Input) -> String, (Input) -> Input, (Input, String, SampleContext) -> Prepared, (Prepared, ResetContext) -> Unit, @model.SetupPolicy) -> Self[Scale, Input, Prepared]
```

The arguments follow the field order.

```moonbit
test "a fixture with a workspace" {
  let resets = Ref(0)
  let fixture : @fixture.Fixture[Int, Array[Double], (Array[Double], Array[Double])] = @fixture.Fixture::new(
    "vector",
    "1",
    context => Array::make(context.dataset_key.scale, 1.0),
    xs => "len=" + xs.length().to_string(),
    xs => xs.copy(),
    (xs, _, _) => (xs, Array::make(xs.length(), 0.0)),
    (_, _) => resets.val += 1,
    @model.SetupPolicy::new(
      @model.SetupFrequency::PerBatch,
      @model.SetupTiming::ExcludedFromMeasurement,
      @model.WorkspaceScope::BatchWorkspace,
    ),
  )
  let context = @model.GenerationContext::new(1UL, "s", "axpy", @model.DatasetKey::new(3, 0), fixture.id, fixture.version)
  let input = @fixture.materialize(fixture, context)
  let (x, workspace) = @fixture.prepare(fixture, input, "axpy", @fixture.SampleContext::new(0, "axpy", 0))
  (fixture.reset)((x, workspace), @fixture.ResetContext::new(0, "axpy"))
  inspect(workspace.length(), content="3")
  inspect(resets.val, content="1")
}
```

### `Fixture::immutable`

`Fixture::immutable` builds a fixture for inputs that are never modified.

```mbti
pub fn[Scale, Input] Fixture::immutable(String, String, (@model.GenerationContext[Scale]) -> Input, (Input) -> String) -> Self[Scale, Input, Input]
```

`clone_input` and `prepare` return their argument, `reset` does nothing, and
the setup policy is `PerDataset`, `ExcludedFromMeasurement`,
`DatasetWorkspace`.

```moonbit
test "an immutable fixture" {
  let fixture = @fixture.Fixture::immutable("numbers", "1", context => context.dataset_key.scale * 10, (n : Int) => n.to_string())
  inspect(fixture.setup_policy.frequency is PerDataset, content="true")
  let context = @model.GenerationContext::new(0UL, "s", "c", @model.DatasetKey::new(4, 0), "numbers", "1")
  inspect(@fixture.materialize(fixture, context), content="40")
}
```

### `materialize`

`materialize` calls a fixture's `materialize` function.

```mbti
pub fn[Scale, Input, Prepared] materialize(Fixture[Scale, Input, Prepared], @model.GenerationContext[Scale]) -> Input
```

### `prepare`

`prepare` calls a fixture's `prepare` function.

```mbti
pub fn[Scale, Input, Prepared] prepare(Fixture[Scale, Input, Prepared], Input, String, SampleContext) -> Prepared
```

It does not call `clone_input`; the runner clones before preparing.

## Contexts

### `SampleContext`

`SampleContext` tells `prepare` which sample and implementation it prepares
for.

```mbti
pub struct SampleContext {
  sample_id : Int
  implementation_id : String
  repetition_id : Int
}
pub fn SampleContext::new(Int, String, Int) -> Self
```

The runner passes the same value as `sample_id` and `repetition_id`; negative
ids mark validation, warmup, calibration and exploratory batches (see the
[runner design](../design/runner.md#fixture-lifecycle-and-sentinel-sample-ids)).

### `ResetContext`

`ResetContext` tells `reset` which sample and implementation it resets.

```mbti
pub struct ResetContext {
  sample_id : Int
  implementation_id : String
}
pub fn ResetContext::new(Int, String) -> Self
```
