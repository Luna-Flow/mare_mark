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
