# Architecture

`mare_mark` keeps the meaning of an experiment, its effects and its
presentation apart. That separation lets a report be regenerated from its
record, a failure be replayed from its artifact, and a decision be recomputed
from raw observations.

## Layers

| Layer | Packages | Owns |
| --- | --- | --- |
| Vocabulary | `model` | versions, protocols, environments, outcomes, events, decisions |
| Inputs | `generator`, `fixture` | seeds, fingerprints, input lifecycle and setup timing |
| Correctness | `experiment` | oracles, shrinking, crossover analysis |
| Measurement | `runner` | the only loop that executes payloads and reads the clock |
| Record | `event`, `ir_sink` | sinks and the append-only JSONL record |
| Analysis | `stats`, `tune`, `tune_gemm` | summaries, comparisons, tuning policy, the GEMM domain |
| Presentation | `ir_model`, `report` | Plot IR and its JSON, SVG and HTML renderings |
| Adapter | `cli` | files, standard streams, process execution, exit codes |

The import graph (test-only imports omitted) is acyclic:

| Package | Imports |
| --- | --- |
| `model` | nothing |
| `generator`, `fixture`, `experiment`, `event`, `ir_model`, `stats`, `tune_gemm` | `model` (and `generator` also `moonbitlang/x/crypto`) |
| `ir_sink` | `event` |
| `runner` | `model`, `fixture`, `event`, `experiment`, `moonbitlang/async` |
| `report` | `model`, `ir_model` |
| `tune` | `runner` |
| `cli` | `model`, `ir_model`, `report`, `moonbitlang/x`, `moonbitlang/async` |

Nothing imports `cli`. `stats` and `report` do not depend on `runner`, so they
can analyse and render records produced elsewhere.

## Data flow

```text
RunProtocol ──validate_protocol──▶ ValidatedProtocol ─┐
BenchSpec ────────compile────────▶ ValidatedBenchPlan ├─▶ runner.run ─▶ ObservationSink
seed, EnvironmentSnapshot, sink ───────────────────────┘        │            │
                                                                 │      JSONL record
   per dataset:  materialize ─▶ fingerprint ─▶ validate ─▶ warmup         │
                 ─▶ calibrate ─▶ exploratory blocks ─▶ confirmatory blocks │
                                                                           ▼
                stats (paired comparisons)      report.document_from_jsonl ─▶ PlotDocument
                tune (scores, selection)                   │
                                                 plot_json · plot_svg · html
```

Everything before `run` is a description that is validated before it can run.
Everything after `run` consumes preserved events. `run` is the only place
where payloads execute and the clock is read; `cli` is the only place that
touches files and processes.

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
applied only to derived views.

**Reports.** `report` is a pure projection. Invalid observations, discarded
batches and series of implementations that failed validation are excluded
from plots, and the failures are shown in the differential section.

**Tuning.** `tune` and `tune_gemm` hold policy and domain data. Building,
validating and measuring candidates is done by the application with `runner`,
so tuning measurements carry the same evidence as any other benchmark.

## Reproducibility

A result is determined by five recorded inputs: the plan (case id,
implementations and their versions, fixture id and version), the validated
protocol, the run seed, the environment snapshot, and the code revision in the
snapshot's provenance. Inputs are derived from the seed by
[`generator`](design/generator.md), the implementation order is derived from
the seed, and the bootstrap is seeded, so everything except the timings
themselves is bit-reproducible on every target. Timings are comparable across
runs when `environment_compatible` holds.

## Targets

All packages build on every target. `runner.run` and `execute_operation` are
`async` and need the `moonbitlang/async` runtime (native, JS, wasm). Subprocess
workers, `mare-mark replay` and stdin/stdout reports are native only; the
non-native `cli` entry point supports file-to-file reports. Native and JS
timings are different populations; compare them only as separately labelled
runs.
