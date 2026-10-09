# Architecture

`mare_mark` keeps the meaning of an experiment, its effects and its
presentation apart. That separation lets a report be regenerated from its
record, a failure be replayed from its artifact, and a decision be recomputed
from raw observations.

## Layers

| Layer | Packages | Owns |
| --- | --- | --- |
| Vocabulary | `model` | versions, protocols, environments, outcomes, events, decisions |
| Environment | `env_detect` | snapshots of the running process: target, runtime, CPU, OS, host, time, revision, run id |
| Inputs | `generator`, `fixture` | seeds, fingerprints, input lifecycle and setup timing |
| Correctness | `experiment` | oracles, shrinking, crossover analysis |
| Measurement | `runner` | the only loop that executes payloads and reads the clock |
| Record | `event`, `ir_sink` | sinks and the append-only JSONL record |
| Analysis | `stats`, `tune`, `tune_gemm` | summaries, comparisons, tuning policy, the GEMM domain |
| Presentation | `ir_model`, `report` | Plot IR, the paired comparisons of a record, and their JSON, SVG, HTML and text renderings |
| Adapter | `cli` | files, standard streams, process execution, exit codes |

The import graph (test-only imports omitted) is acyclic:

| Package | Imports |
| --- | --- |
| `model` | nothing |
| `generator`, `fixture`, `experiment`, `event`, `ir_model`, `stats`, `tune_gemm` | `model` (and `generator` also `moonbitlang/x/crypto`) |
| `env_detect` | `model`, `moonbitlang/async`, `moonbitlang/x/fs` |
| `ir_sink` | `event` |
| `runner` | `model`, `fixture`, `event`, `experiment`, `moonbitlang/async` |
| `report` | `model`, `event`, `ir_model`, `stats` |
| `tune` | `runner` |
| `cli` | `model`, `ir_model`, `report`, `moonbitlang/x`, `moonbitlang/async` |

Nothing imports `cli` or `env_detect`: the program that runs a benchmark calls
`env_detect` and hands the snapshot to the runner, so the runner never probes
the host. `stats` and `report` do not depend on `runner`, so they can analyse
and render records produced elsewhere; `report` reads the recorded protocol
through `event` and decides with `stats`.

## Data flow

```text
RunProtocol ──validate_protocol──▶ ValidatedProtocol ─┐
BenchSpec ────────compile────────▶ ValidatedBenchPlan ├─▶ runner.run ─▶ ObservationSink
env_detect.detect ─▶ EnvironmentSnapshot, seed, sink ─┘        │            │
                                                                 │      JSONL record
   per scale, per dataset of the design:                         │  (summary: protocol,
     materialize ─▶ fingerprint ─▶ validate (coverage)            │   seed, environment)
     ─▶ warmup ─▶ calibrate (first dataset of the scale only)     │            │
     ─▶ the dataset's blocks (exploratory, then confirmatory)     │            ▼
                                                     report.document_from_jsonl(baseline?)
                stats (paired comparisons)              │ plots + comparisons
                tune (scores, selection)                ▼
                                 PlotDocument ─▶ plot_json · plot_svg · html · comparisons_text
```

Everything before `run` is a description that is validated before it can run.
Everything after `run` consumes preserved events. `run` is the only place
where payloads execute and the timing clock is read. Processes are started by
`runner` (subprocess workers), by `env_detect` (probing the host on native)
and by `cli` (replay); files are read and written only by `env_detect`
(`/proc/cpuinfo`) and `cli`.

## Boundaries between packages

**Timing.** The timed region contains the payload and the output fold, plus
setup only when the fixture's `SetupPolicy` includes it. Validation, warmup,
calibration, event emission, the sink's `finish`, statistics and rendering are
outside. The [runner design](design/runner.md) has the exact table.

**Failure.** An operation's failure is a value (`ExecutionOutcome`), a
validation's verdict is a value (`ValidationStatus`), and a failing validation
emits a `ValidationFailure` with a minimized input and a replay command. A
timeout or crash is infrastructure evidence, never a slow measurement.

**Statistics.** Raw observations are never filtered or aggregated in the
record. `stats` computes decisions from paired arrays; `OutlierPolicy` is
applied only to derived values, and the report applies the recorded policy to
paired deltas, never to stored observations.

**Reports.** `report` is a pure projection. It plots and compares only
confirmatory observations; invalid observations, discarded batches and the
timings of implementations that failed validation on a dataset are excluded,
and the failures are shown in the differential section. Its comparisons use
the threshold, outlier policy and seed recorded in the run, or stated
defaults for older records.

**Tuning.** `tune` and `tune_gemm` hold policy and domain data. Building,
validating and measuring candidates is done by the application with `runner`,
so tuning measurements carry the same evidence as any other benchmark.

## Reproducibility

A result is determined by five recorded inputs: the plan (case id,
implementations and their versions, fixture id and version), the validated
protocol, the run seed, the environment snapshot, and the code revision in the
snapshot's provenance. The JSONL summary carries the protocol, the seed and
the snapshot, and its `run_id` combines the case, the protocol identity, the
seed and the provenance run id and timestamp, so every run is identified and
can be re-analysed. Inputs are derived from the seed by
[`generator`](design/generator.md), the implementation order is derived from
the seed, and the bootstrap is seeded, so everything except the timings
themselves is bit-reproducible on every target. Timings are comparable across
runs when `environment_compatible` holds.

## Targets

All packages build on every target. `runner.run`, `execute_operation` and
`env_detect.detect` are `async` and need the `moonbitlang/async` runtime
(native, JS, wasm). Subprocess workers, `mare-mark replay` and stdin/stdout
reports are native only; the non-native `cli` entry point supports
file-to-file reports. `env_detect` probes the host on native and Node.js and
reads environment variables elsewhere. Native and JS
timings are different populations; compare them only as separately labelled
runs.
