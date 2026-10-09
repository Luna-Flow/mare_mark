# env_detect tutorial

This tutorial replaces the hand-written environment snapshot of a run with a
detected one: you detect the environment and run a benchmark with it, fill in
what cannot be detected, check what is missing before you trust a result, and
set the toolchain in CI. Every example is a complete `async test`; the outputs
shown are the parts that do not depend on your machine.

| I want to | Use |
| --- | --- |
| describe the machine without writing it down | `@env_detect.detect()` and its `snapshot` |
| state what the process cannot know (flags, ABI, parallelism) | the labelled arguments of `detect` |
| pin a field for a reproducible record | the same labelled arguments |
| see which fields are only fallbacks | `DetectedEnvironment.undetected` |
| record the compiler version in CI | the `MARE_MARK_TOOLCHAIN` environment variable |
| make a run id without detecting anything | `@env_detect.new_run_id(@env.now())` |

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/env_detect",
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/runner",
  "moonbitlang/async",
}
```

Detect the environment and hand its snapshot to the runner:

```moonbit
async test "a run with a detected environment" {
  let doubled = @runner.Implementation::stateless("add", "1", (n : Int) => {
    @model.OperationResult::completed(n + n, ())
  })
  let shifted = @runner.Implementation::stateless("shift", "1", (n : Int) => {
    @model.OperationResult::completed(n << 1, ())
  })
  let plan = @runner.single_step("double", [1, 1000])
    .with_immutable_input(context => context.dataset_key.scale, n => n.to_string())
    .compare([doubled, shifted])
    .against_equal(n => 2 * n, (expected, actual) => expected == actual)
    .compile()
    .unwrap()
  let detected = @env_detect.detect(compiler_flags="debug", concurrency=1)
  let memory = @event.InMemorySink::new()
  let summary = @runner.run(
    plan,
    @runner.RunContext::new(detected.snapshot, memory.as_sink(), 42UL, @runner.ProtocolPreset::QuickCheck.validated()),
  )
  inspect(summary.passed_count, content="4")
  inspect(summary.environment.unwrap().performance.concurrency, content="1")
}
```

`detect` filled in the target, the runtime, the CPU, the operating system, the
host name, the time, the revision when it could find one, and a fresh run id.
It cannot know how the code was compiled or how many operations the benchmark
runs at once, so the test states both. The snapshot travels with the run: it
is in the returned summary and in the `summary` line of a JSONL record.

## Everyday tasks

### Say what the process cannot know

Four fields describe your build and your benchmark rather than the machine,
and `detect` never guesses them:

| Argument | What to pass |
| --- | --- |
| `compiler_flags` | how the code under test was built, for example `"release"` or `"--release -O3"` |
| `dtype_abi` | the numeric representation the results depend on, for example `"f64"` or `"i64"` |
| `toolchain` | the compiler version, unless `MARE_MARK_TOOLCHAIN` is set |
| `concurrency` | how many operations the benchmark runs at once: `1` for the runner's sequential loop |

These are semantic or performance fields, so `@model.environment_compatible`
compares them: two runs built with different flags are not comparable, which
is what you want.

```moonbit
async test "state the build and the parallelism" {
  let detected = @env_detect.detect(
    toolchain="moonc 0.10",
    compiler_flags="release",
    dtype_abi="f64",
    concurrency=1,
  )
  let semantic = detected.snapshot.semantic
  inspect(semantic.compiler_flags, content="release")
  inspect(semantic.dtype_abi, content="f64")
  inspect(detected.undetected.contains("toolchain"), content="false")
  inspect(detected.undetected.contains("concurrency"), content="false")
}
```

### Pin a field

Any field can be overridden, detected or not. Pin the ones that must not
change between the runs you want to compare, or that the probe gets wrong on
your machine, for example a CPU name that differs between otherwise identical
CI runners:

```moonbit
async test "pin the CPU description and the run id" {
  let detected = @env_detect.detect(
    cpu="ci-standard-4",
    run_id="nightly-2026-10-09",
    compiler_flags="release",
    dtype_abi="f64",
    concurrency=1,
  )
  inspect(detected.snapshot.performance.cpu, content="ci-standard-4")
  inspect(detected.snapshot.provenance.run_id, content="nightly-2026-10-09")
  inspect(detected.undetected.contains("cpu"), content="false")
}
```

### Check what is missing before trusting a run

`undetected` lists every field that holds a fallback. Two runs whose `cpu` is
`"unknown"` look compatible to `environment_compatible`, because
`"unknown" == "unknown"`, so check the list before you compare runs or gate a
release on them:

```moonbit
fn missing(detected : @env_detect.DetectedEnvironment, required : Array[String]) -> Array[String] {
  required.filter(field => detected.undetected.contains(field))
}

async test "require the fields a comparison relies on" {
  let detected = @env_detect.detect(compiler_flags="release", dtype_abi="f64", concurrency=1)
  // The defaults of clock, device and frequency_policy are listed too.
  debug_inspect(missing(detected, ["clock", "compiler_flags"]), content="[\"clock\"]")
  // In a gate, fail when a field you rely on is missing.
  let gaps = missing(detected, ["target", "timestamp"])
  if !gaps.is_empty() {
    fail("undetected: " + gaps.join(", "))
  }
}
```

The fields `target`, `gc`, `timestamp` and `run_id` always have a value; the
others depend on the target and the host. On native and Node.js the CPU, the
OS and the host name are usually found; in a browser and on wasm they come
only from environment variables, if at all.

### Record the toolchain in CI

The compiler version is not visible to the running program. Set it in the
environment of the test or benchmark job:

```sh
export MARE_MARK_TOOLCHAIN="moonc $(moonc -v)"
moon test --target native
```

`detect` reads `MARE_MARK_TOOLCHAIN` for `toolchain`. On GitHub Actions and
GitLab CI the revision comes from `GITHUB_SHA` or `CI_COMMIT_SHA` without any
setup; elsewhere set `GIT_COMMIT`, or let the native build ask
`git rev-parse HEAD`.

### Make a run id on its own

`new_run_id` is the generator `detect` uses for `run_id`. Call it when you
build a snapshot by hand but still want a unique, time-ordered id:

```moonbit
test "a run id for a hand-written snapshot" {
  let run_id = @env_detect.new_run_id(1791529902123UL)
  inspect(run_id.has_prefix("20261009T071142123Z-"), content="true")
}
```

Pass `@env.now()` (from `moonbitlang/core/env`) as the argument to stamp the
current time.

## Going further

- **Hand-written snapshots still work.** The `@model` constructors remain the
  way to describe a machine you are not running on, or to write a fully
  deterministic test; see the [model tutorial](model.md).
- **The record keeps the snapshot.** A JSONL `summary` carries the
  `environment` object, so a report or a later comparison sees the same
  fields; see the [event API](../api/event.md#jsonl-records).
- **Run ids.** The runner's `RunSummary.run_id` includes the provenance
  `run_id` and `timestamp`, so a detected environment makes every run id
  unique; see the [model API](../api/model.md#run_identity).

## Common pitfalls

- **Expecting the core count in `concurrency`.** It is in the `cpu` text.
  `concurrency` is the benchmark's own parallelism and stays
  `UNKNOWN_CONCURRENCY` (`0`) unless you pass it.
- **Comparing runs with undetected fields.** `"unknown"` equals `"unknown"`;
  check `undetected` first.
- **Calling `detect` outside an async context.** It is an `async fn`; on
  wasm-gc there is no async runtime, so build the snapshot by hand there.
- **Expecting detected text to be stable across upgrades.** `runtime`
  includes the Node.js version and `cpu` the core count, so an upgraded
  runner image is a different performance environment. Pin the field if that
  is not what you want.
- **Relying on `seq<n>` run ids across processes.** Without an entropy source
  the suffix is a per-process counter; two processes started in the same
  millisecond get the same id.

## Next steps

- [env_detect API](../api/env_detect.md) and
  [env_detect design](../design/env_detect.md).
- [runner tutorial](runner.md) to run benchmarks with the snapshot.
- [model tutorial](model.md) for environment compatibility.
