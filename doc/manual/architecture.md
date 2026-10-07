# Architecture

`mare_mark` keeps experiment semantics, effects, and presentation separate.
That separation lets a report be regenerated, a failure be replayed, and a
statistical decision be audited from raw observations.

| Layer | Packages | Owns |
| --- | --- | --- |
| Domain model | `model`, `ir_model`, `tune_gemm` | Versioned protocol, events, plots, candidate data |
| Pure policy | `generator`, `experiment`, `stats`, `tune`, `report` | Seeds, oracles, summaries, decisions, rendering |
| Runtime effects | `fixture`, `runner` | Setup, workers, clocks, synchronization |
| Adapters | `event`, `ir_sink`, `cli` | JSONL sinks, file IO, command-line effects |

## Data flow

```text
configuration
  -> BenchSpec
  -> compile / validate
  -> GenerationContext(seed, suite, case, dataset)
  -> Fixture(materialize, prepare, reset)
  -> Oracle validation
  -> calibration outside timing
  -> balanced timed blocks
  -> ObservationSink(JSONL)
  -> stats / differential summary
  -> PlotDocument
  -> SVG or self-contained HTML
```

The only broad effect boundary is `runner.run`. Everything before it is a
description or validation step; everything after it consumes preserved events.
`cli` is the place where file paths, stdin/stdout, `open`, and replayed process
execution are allowed.

## Timing boundary

The timed closure includes payload execution and the configured output fold. It
excludes fixture materialization, validation, calibration, final sink
conversion, report rendering, and file IO. A fixture may opt into setup timing,
but that choice must be represented by `SetupPolicy` and reported with the
result.

Each balanced block rotates implementation order. This controls systematic
position effects; it does not make unrelated machines comparable. Pair values
by dataset, repetition, and block before computing deltas.

## Failure boundary

The runner preserves a typed `ExecutionOutcome` and optional next context. A
validation failure carries enough information for a replay artifact: input
text/fingerprint, implementation version, command/arguments, timeout, and
shrinker path. A timeout or process abort is infrastructure evidence, not a
slow numeric observation.

## Report boundary

`event` JSONL is append-only. `report.document_from_jsonl` maps it to `ir_model`
and applies projection rules: valid observations feed plots, while failures,
discarded batches, capability notes, and corpus counters remain visible in the
differential report. `report.html` is pure and deterministic for one
`PlotDocument`.

## Tuning boundary

`tune` and `tune_gemm` model candidate search, score, holdout, and Pareto
policy. They do not hide candidate execution, build configuration, correctness
validation, or environment capture. The application chooses those effects and
emits the same events as a hand-written benchmark.
