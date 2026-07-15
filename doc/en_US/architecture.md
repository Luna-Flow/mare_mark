# Architecture

mare_mark separates pure experiment description and report projection from
timing and file-system effects.

| Layer | Packages | Responsibility |
| --- | --- | --- |
| Domain model | `model`, `ir_model`, `tune_gemm` | Protocol, event, plot, and tuning data. |
| Pure transforms | `generator`, `stats`, `experiment`, `tune`, `report` | Seeds, summaries, decisions, policies, and rendering. |
| Controlled runtime | `fixture`, `runner` | Materialization, preparation, monotonic timing, reset. |
| Effect adapters | `event`, `ir_sink`, `cli` | Event accumulation and native file IO. |

## Measurement flow

```text
BenchSpec -> compile -> ValidatedBenchPlan
          -> GenerationContext -> Fixture -> Oracle/Worker -> ValidationFailure
                  -> balanced timed blocks -> streaming ObservationSink
                  -> JSONL -> DifferentialReport + PlotDocument -> HTML
```

The payload closure does not perform report rendering or file IO. `report`
remains a pure `PlotDocument -> String` boundary; only `cli` reads and writes
files.

## Explicit boundaries

`run(plan, context)` is the thin effect boundary. It calibrates batches outside
the measurement phase and emits separate
exploratory and confirmatory observations. The tuning packages provide search
and policy data models; applications own domain-specific microkernel
registration and execution.
