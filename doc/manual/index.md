# mare_mark

`mare_mark` is a benchmarking harness for MoonBit. It validates every
implementation against an oracle before timing it, measures in calibrated
batches and balanced blocks, keeps every raw observation in an append-only
JSONL record, compares implementations with robust, paired statistics and a
seeded bootstrap, supports auto-tuning with practical ties and Pareto fronts,
and renders self-contained HTML reports. This manual describes version
`0.3.0`; the `pkg.generated.mbti` file of each package is the authority for its
public names and signatures.

## Packages

| Package | Role | Pages |
| --- | --- | --- |
| `model` | shared vocabulary: versions, protocols, environments, outcomes, events, decisions | [API](api/model.md) · [tutorial](tutorial/model.md) · [design](design/model.md) |
| `generator` | seed derivation and input fingerprints | [API](api/generator.md) · [tutorial](tutorial/generator.md) · [design](design/generator.md) |
| `fixture` | input lifecycle and setup timing | [API](api/fixture.md) · [tutorial](tutorial/fixture.md) · [design](design/fixture.md) |
| `experiment` | oracles, shrinking, crossover analysis | [API](api/experiment.md) · [tutorial](tutorial/experiment.md) · [design](design/experiment.md) |
| `runner` | the measurement loop: validation, warmup, calibration, balanced blocks | [API](api/runner.md) · [tutorial](tutorial/runner.md) · [design](design/runner.md) |
| `event` | sinks and the JSONL record | [API](api/event.md) · [tutorial](tutorial/event.md) · [design](design/event.md) |
| `ir_sink` | short constructors for the common sinks | [API](api/ir_sink.md) · [tutorial](tutorial/ir_sink.md) · [design](design/ir_sink.md) |
| `stats` | summaries, paired comparisons, bootstrap intervals, outlier views | [API](api/stats.md) · [tutorial](tutorial/stats.md) · [design](design/stats.md) |
| `ir_model` | Plot IR: plots and differential evidence | [API](api/ir_model.md) · [tutorial](tutorial/ir_model.md) · [design](design/ir_model.md) |
| `report` | JSONL to Plot IR to JSON, SVG and HTML | [API](api/report.md) · [tutorial](tutorial/report.md) · [design](design/report.md) |
| `tune` | tuning policy: scores, selection, Pareto fronts, seeded subsets | [API](api/tune.md) · [tutorial](tutorial/tune.md) · [design](design/tune.md) |
| `tune_gemm` | worked tuning domain: blocked matrix multiplication | [API](api/tune_gemm.md) · [tutorial](tutorial/tune_gemm.md) · [design](design/tune_gemm.md) |
| `cli` | the `mare-mark` executable: `report` and guarded `replay` | [API](api/cli.md) · [tutorial](tutorial/cli.md) · [design](design/cli.md) |

The guides span packages: [getting started](getting_started.md),
[architecture](architecture.md), [verification](verification.md) and the
[repository conventions](conventions.md). The repository has no doc-test
packages; the examples in this manual are compiled and run against the
released packages as described in [verification](verification.md).

## Reading paths

**New to benchmarking with mare_mark.** Read [getting started](getting_started.md),
then the [runner tutorial](tutorial/runner.md) and the
[stats tutorial](tutorial/stats.md). Publish with the
[report tutorial](tutorial/report.md).

**Using it in a project.** Keep the API pages of `runner`, `stats` and `model`
at hand; read the [fixture](tutorial/fixture.md) and
[generator](tutorial/generator.md) tutorials for realistic inputs, and the
[experiment tutorial](tutorial/experiment.md) for oracles and crossovers. For
tuning, read [tune](tutorial/tune.md) and [tune_gemm](tutorial/tune_gemm.md).

**Reviewing results or contributing.** Read the [architecture](architecture.md)
and the design pages, starting with [runner](design/runner.md) (experimental
design and calibration) and [stats](design/stats.md) (estimators, bootstrap and
decision rule), then [verification](verification.md).

## Toolchain and installation

mare_mark needs MoonBit with `moonc` 0.10 or later. It depends on
`moonbitlang/x` 0.5.5 and `moonbitlang/async` 0.22.4.

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

Every package compiles on all MoonBit targets. `runner.run` is asynchronous and
runs where `moonbitlang/async` has a runtime: native, JS and wasm (not
wasm-gc). Subprocess workers, the `replay` command and stdin/stdout reports
need the native target.

## Stability

mare_mark is pre-1.0. The versioned contracts are the protocol vocabulary
`mmkp_1`, the JSONL artifacts `mmka_1`, the Plot IR schema `mmks_1` and the
GEMM tuning configuration `mmkts_1`; readers reject other versions. Timing
thresholds, candidate enumeration, HTML styling and private layouts are not
compatibility promises. Each design page ends with the package's boundaries.
