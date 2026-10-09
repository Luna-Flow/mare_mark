# env_detect API

## Purpose

`Luna-Flow/mare_mark/env_detect` fills a `model.EnvironmentSnapshot` from what
the running process can find out about itself: the compilation target, the
runtime and memory management, the operating system, the host name, the CPU
model with its logical core count, the current time, the source revision and a
fresh run id. A run then needs no hand-written environment. Detection never
fails and never guesses: a field it cannot find holds a documented fallback
and is listed in `undetected`, and every field can be overridden. The reasons
for this shape are in the [env_detect design](../design/env_detect.md).

Source: [`src/env_detect/env_detect.mbt`](../../../src/env_detect/env_detect.mbt),
[`src/env_detect/target.mbt`](../../../src/env_detect/target.mbt) and the
per-target probes [`probe_native.mbt`](../../../src/env_detect/probe_native.mbt),
[`probe_js.mbt`](../../../src/env_detect/probe_js.mbt) and
[`probe_none.mbt`](../../../src/env_detect/probe_none.mbt).

## Importing

Add the packages to the `moon.pkg` of the package that uses them:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/env_detect",
  "moonbitlang/async",
}
```

The examples on this page call them through their default aliases (`@model`,
`@env_detect`). `moonbitlang/async` is needed because `detect` is `async`:
call it from an `async fn main` or an `async test`, like `runner.run`. The
package builds on every target; `detect` runs where `moonbitlang/async` has a
runtime (native, JS, wasm), and `new_run_id` is an ordinary function that runs
everywhere.

## Detection

### `detect`

`detect` builds the environment snapshot of the running process.

```mbti
pub async fn detect(target? : @model.ExecutionTarget, toolchain? : String, compiler_flags? : String, dtype_abi? : String, runtime? : String, cpu? : String, gc? : String, concurrency? : Int, clock? : String, device? : String, frequency_policy? : String, os? : String, hostname? : String, timestamp? : String, revision? : String, run_id? : String) -> DetectedEnvironment
```

Every argument is optional and named after the snapshot field it sets. A
field passed as an argument is used as it is: it is not probed and never
appears in `undetected`. For every other field `detect` does the following.

| Field | Part | Value when not overridden |
| --- | --- | --- |
| `target` | semantic | the target the code was compiled for (`Native`, `Js`, `Wasm`, `WasmGc` or `Llvm`) |
| `toolchain` | semantic | the `MARE_MARK_TOOLCHAIN` environment variable, else `UNKNOWN` |
| `compiler_flags` | semantic | never detected: `UNKNOWN` |
| `dtype_abi` | semantic | never detected: `UNKNOWN` |
| `runtime` | performance | `"native"` on native and LLVM, `"node <version>"` on Node.js, else `UNKNOWN` |
| `cpu` | performance | the CPU model followed by the logical core count, for example `"Apple M4 (10 logical cores)"`, else `UNKNOWN` |
| `gc` | performance | the memory management of the target: `"rc"` on native, LLVM and wasm, `"wasm-gc"` on wasm-gc, `"js-engine"` on JS |
| `concurrency` | performance | never detected: `UNKNOWN_CONCURRENCY` |
| `clock` | performance | never detected: `DEFAULT_CLOCK` |
| `device` | performance | never detected: `DEFAULT_DEVICE` |
| `frequency_policy` | performance | never detected: `DEFAULT_FREQUENCY_POLICY` |
| `os` | provenance | the operating system and its release, for example `"Darwin 24.1.0"`, else `UNKNOWN` |
| `hostname` | provenance | the host name, else `UNKNOWN` |
| `timestamp` | provenance | the current UTC time as `YYYY-MM-DDTHH:MM:SSZ` |
| `revision` | provenance | `GITHUB_SHA`, `CI_COMMIT_SHA` or `GIT_COMMIT`, else `git rev-parse HEAD` on native, else `UNKNOWN` |
| `run_id` | provenance | `new_run_id` of the same instant as `timestamp` |

`target`, `gc`, `timestamp` and `run_id` always have a value and are never
reported as undetected. When only one half of the CPU text is known, `cpu` is
the model alone, or `"unknown (10 logical cores)"` with only the count; it is
undetected only when neither is known. Environment variables are read
trimmed, and a variable that is set to blanks counts as unset. The
[env_detect design](../design/env_detect.md#what-each-target-can-detect) lists
the probe of every field on every target.

`concurrency` is the degree of parallelism of the benchmark itself (`1` for a
benchmark that runs one operation at a time), which the process cannot know.
The logical core count of the machine is part of `cpu`, not `concurrency`.

On native, detection runs up to five short subprocesses (`uname` twice,
`getconf`, `sysctl` when `/proc/cpuinfo` has no model, `git`); each is given at
most 5 seconds, and a command that is missing, fails or times out only leaves
its field undetected. On other targets `detect` does not suspend.

```moonbit
async test "overrides are used as given" {
  let detected = @env_detect.detect(
    toolchain="moonc 0.10",
    compiler_flags="release",
    dtype_abi="f64",
    concurrency=1,
    hostname="bench-1",
  )
  let snapshot = detected.snapshot
  inspect(snapshot.semantic.toolchain, content="moonc 0.10")
  inspect(snapshot.performance.concurrency, content="1")
  inspect(snapshot.provenance.hostname, content="bench-1")
  inspect(detected.undetected.contains("compiler_flags"), content="false")
  inspect(detected.undetected.contains("clock"), content="true")
  inspect(snapshot.performance.clock, content="monotonic")
}
```

### `DetectedEnvironment`

`DetectedEnvironment` is the result of `detect`: the snapshot and the fields
that hold a fallback.

```mbti
pub struct DetectedEnvironment {
  snapshot : @model.EnvironmentSnapshot
  undetected : Array[String]
}
```

`snapshot` is an ordinary `EnvironmentSnapshot`; pass it to
`@runner.RunContext::new`. `undetected` names the fields that were neither
detected nor overridden, as they are spelled in the JSONL record
(`"toolchain"`, `"cpu"`, `"concurrency"`, ...), each once and in snapshot
order: `toolchain`, `compiler_flags`, `dtype_abi`, `runtime`, `cpu`,
`concurrency`, `clock`, `device`, `frequency_policy`, `os`, `hostname`,
`revision`. A field is in the list exactly when it holds `UNKNOWN`,
`UNKNOWN_CONCURRENCY` or its `DEFAULT_*` constant because nothing better was
known.

```moonbit
async test "nothing is undetected when everything is given" {
  let detected = @env_detect.detect(
    target=@model.ExecutionTarget::Native,
    toolchain="moonc 0.10",
    compiler_flags="release",
    dtype_abi="f64",
    runtime="native",
    cpu="Apple M4 (10 logical cores)",
    gc="rc",
    concurrency=1,
    clock="monotonic",
    device="host",
    frequency_policy="uncontrolled",
    os="Darwin 24.1.0",
    hostname="bench-1",
    timestamp="2026-10-09T08:00:00Z",
    revision="628d39e",
    run_id="nightly-17",
  )
  inspect(detected.undetected.length(), content="0")
  inspect(detected.snapshot.provenance.run_id, content="nightly-17")
}
```

## Run ids

### `new_run_id`

`new_run_id` makes a run id for a run that starts at the given time.

```mbti
pub fn new_run_id(UInt64) -> String
```

The argument is the time in milliseconds since the Unix epoch, as returned by
`@env.now()`. The id is the UTC time in the basic ISO 8601 form with
milliseconds, a hyphen, and 16 lowercase hexadecimal digits from 8 bytes of
the platform's entropy source:

```text
YYYYMMDDTHHMMSSmmmZ-<16 hex digits>      20261009T071142123Z-9f2c4e01a7b3d856
```

When the platform has no entropy source (wasm-gc, or a host that refuses the
request) the suffix is `seq<n>`, where `n` counts the calls in the current
process; such an id is unique only within that process. Ids sort by time
because every field has a fixed width.

```moonbit
test "run ids start with the UTC time" {
  let first = @env_detect.new_run_id(0UL)
  let second = @env_detect.new_run_id(0UL)
  inspect(first.has_prefix("19700101T000000000Z-"), content="true")
  inspect(first != second, content="true")
  inspect(@env_detect.new_run_id(1791529902123UL).has_prefix("20261009T071142123Z-"), content="true")
}
```

## Fallback values

### `UNKNOWN`

`UNKNOWN` is the value of a text field that was neither detected nor
overridden.

```mbti
pub const UNKNOWN : String = "unknown"
```

### `UNKNOWN_CONCURRENCY`

`UNKNOWN_CONCURRENCY` is the value of `concurrency` when it is not overridden.

```mbti
pub const UNKNOWN_CONCURRENCY : Int = 0
```

No benchmark runs with a parallelism of $0$, so the value cannot be mistaken
for a real one.

### `DEFAULT_CLOCK`, `DEFAULT_DEVICE`, `DEFAULT_FREQUENCY_POLICY`

These constants are the values of `clock`, `device` and `frequency_policy`
when they are not overridden.

```mbti
pub const DEFAULT_CLOCK : String = "monotonic"
pub const DEFAULT_DEVICE : String = "host"
pub const DEFAULT_FREQUENCY_POLICY : String = "uncontrolled"
```

`DEFAULT_CLOCK` names the monotonic clock of `moonbitlang/core/bench` that the
runner uses on every target; `DEFAULT_DEVICE` and `DEFAULT_FREQUENCY_POLICY`
are the defaults of `@model.PerformanceEnvironment::new`. The three fields are
still listed in `undetected`, because a default is a convention, not an
observation of the machine.

```moonbit
test "fallback constants" {
  inspect(@env_detect.UNKNOWN, content="unknown")
  inspect(@env_detect.UNKNOWN_CONCURRENCY, content="0")
  inspect(@env_detect.DEFAULT_CLOCK, content="monotonic")
  inspect(@env_detect.DEFAULT_DEVICE, content="host")
  inspect(@env_detect.DEFAULT_FREQUENCY_POLICY, content="uncontrolled")
}
```
