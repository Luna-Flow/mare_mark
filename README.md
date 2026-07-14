# Mare Mark

Mare Mark is a reproducible experiment toolkit for MoonBit payloads. It keeps
dataset generation, fixture setup, timed execution, raw observations,
statistical comparison, tuning policy, and report rendering in separate
packages so measurement code stays small and reviewable.

## Current Baseline

Version `0.2.0` provides a stateful differential runner with shared warmup,
seeded balanced execution order, asynchronous synchronization hooks, typed
execution outcomes, reference and relational oracles, native subprocess
isolation, failure shrinking/replay artifacts, streaming JSONL adapters,
median-based statistics, environment compatibility checks, tuning data models,
and self-contained differential HTML reports.

The CLI is an artifact-edge tool and deliberately stays outside benchmark
execution. It provides report generation and native replay:

```sh
moon run src/cli --target native -- report \
  testdata/report/sample.jsonl report.html
```

`replay` executes the worker command captured in a `validation_failure` event
on the native target. Applications construct and run typed benchmark cases
through the package API, so CLI parsing, filesystem access, and rendering can
never enter a timed payload.

## Installation

```sh
moon add Luna-Flow/mare_mark@0.2.0
```

## Package Map

| Package | Responsibility |
| --- | --- |
| `model` | Protocol, environment, observation, validation, crossover, and deployment data. |
| `generator` / `fixture` | Reproducible input context and isolated setup/reset lifecycle. |
| `runner` | Oracle validation, sticky contexts, isolated workers, setup/reset lifecycles, timing, and shrinking. |
| `event` / `ir_sink` | In-memory and callback-streaming JSONL event sinks. |
| `stats` / `experiment` | Robust summaries, paired comparison, outlier reporting, and crossover diagnosis. |
| `ir_model` / `report` | Plot and differential IR, mismatch/capability/corpus tables, SVG, and HTML reports. |
| `tune` / `tune_gemm` | Candidate scoring, Pareto filtering, and GEMM tuning models. |
| `cli` | Artifact replay and JSONL-to-HTML report adapter; never imported by the runner. |

## Documentation

- [English](./doc/en_US/README.md)
- [简体中文](./doc/zh_CN/README.md)
- [日本語](./doc/ja_JP/README.md)
- [English getting started](./doc/en_US/getting_started.md)
- [Architecture](./doc/en_US/architecture.md)
- [Verification](./doc/en_US/verification.md)
- [Documentation standard](./doc/en_US/doc_standard.md)

## Development

```sh
moon check --target js
moon check --target native
moon test
moon info
moon fmt
```

Generated `pkg.generated.mbti` files are the public interface snapshots.
