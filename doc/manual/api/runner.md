# `runner` API

`runner` owns executable benchmark cases and monotonic timed batches.

- `Implementation::in_process` registers a stateful callback; `Implementation::worker` registers a native isolated subprocess. Both accept an optional blocking `synchronize` hook for asynchronous backends.
- `WorkerSpec::new` defines argument encoding, output decoding, timeout, and working directory.
- `OutputSink::new` folds outputs during the timed batch, then retains the finished value with `Bench::keep` after the clock stops.
- `single_step` builds an immutable common-case description; its combinators return new values and `compile` aggregates configuration errors.
- `ValidatedBenchPlan` and `ValidatedProtocol` are the only inputs accepted by the runtime boundary.
- `ProtocolPreset` provides `QuickCheck`, `Development`, `RegressionGate`, and validated custom protocols.
- `RunContext` groups protocol, environment, observation sink, and seed.
- `balanced_order` rotates implementation order by block id.
- `run(plan, context)` fingerprints input, validates every sequence step outside timing, shrinks failures, emits replay artifacts, then measures balanced batches and returns `RunSummary`.

`run` calibrates each implementation toward the configured target batch
time, caps work at the iteration and sample-time bounds, and applies a common
batch size only when `SharedBatchSize` is selected. Exploratory and
confirmatory observations remain separate phases.

The JSONL summary records the complete `EnvironmentSnapshot`, including device,
thread/concurrency count, and frequency policy. Use `stats.summarize` over
repeated valid observations for median-based reporting.

See `src/runner/pkg.generated.mbti` for exact generic signatures.

## Boundary

Only `runner` owns the timed loop. Generators, fixtures, validation oracles,
output conversion, report rendering, and file sinks must remain outside the
payload clock unless the selected `SetupPolicy` explicitly says otherwise.

```text
materialize -> validate -> prepare -> calibrate outside timing
           -> balanced timed batch -> fold -> reset -> emit observation
```

The order matters: a faster implementation that returns a different value is
a validation failure, not a speedup. A timeout, worker exit, or synchronization
failure is also retained as a typed outcome and excluded from performance
statistics.

## Minimal setup

```moonbit nocheck
let plan = @runner.single_step("vector-add", [64, 256, 1024])
  .with_immutable_input(
    ctx => make_input(ctx.dataset_key.scale),
    input => @generator.stable_fingerprint(serialize(input)),
  )
  .compare([baseline, candidate])
  .against_equal(reference, (expected, actual) => expected == actual)
  .compile()
  .unwrap()
```

Construct `RunContext` with an explicit `ValidatedProtocol`, an
`EnvironmentSnapshot`, a seed, and an observation sink. Treat the seed and
environment as part of the result identity; changing either starts a new
measurement series.

## Choosing an implementation

| Constructor | Use when | Timing notes |
| --- | --- | --- |
| `stateless` | output depends only on the input | no mutable context is carried |
| `in_process` | setup/reset or device state is required | provide `synchronize` for queued work |
| `worker` | native isolation or crash containment is required | stdout/stderr/exit are artifacts |

`WorkerSpec::new` owns argument encoding, output decoding, timeout, and working
directory. Do not hide a shell command in a stateless callback: it makes the
clock, failure model, and replay story ambiguous.

## Protocol and phases

`ProtocolPreset::QuickCheck` is for fast feedback; `Development` keeps enough
warmup and repetitions to inspect variance; `RegressionGate` is the strictest
built-in preset. Custom protocols must be validated before `run`.

Warmup, calibration, exploratory, confirmatory, and holdout observations are
separate phases. Calibration adjusts batch size toward the target batch time,
then applies iteration and sample-time caps. `SharedBatchSize` is useful when
paired implementations must execute the same number of operations; otherwise
each implementation may use its own calibrated batch size.

## Failure evidence

When validation fails, `run` shrinks the input when a `Shrinker` is configured,
records the minimal counterexample and shrink path, and emits a replayable
`validation_failure` event. Keep that JSONL event with the report; it explains
why a candidate was rejected even when the remaining observations look good.
