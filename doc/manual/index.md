# mare_mark

This manual documents the `0.3.0` release of `Luna-Flow/mare_mark`.

## Overview

`mare_mark` is a benchmarking harness for MoonBit. It validates every
implementation against an oracle before timing it, measures in calibrated
batches and balanced blocks over one or many datasets per scale, records the
environment it detects together with the full protocol and seed, keeps every
raw observation in an append-only JSONL record, compares implementations with
a baseline using robust, paired statistics and a seeded bootstrap, supports
auto-tuning with practical ties and Pareto fronts, and renders self-contained
HTML reports. The `pkg.generated.mbti` file of each
package is the authority for its public names and signatures.

The release centers on four ideas:

- A fast wrong answer never looks like a speedup: validation precedes timing,
  and a failing implementation is removed from the plots.
- Every number in a report is recomputed from raw observations kept in the
  event stream; nothing is filtered or averaged before it is stored, and the
  record carries the protocol, the seed and the environment needed to do so.
- Decisions compare paired deltas against a practical threshold stated in
  percent, and report the uncertainty next to the decision.
- Randomness is pinned by explicit seeds, so inputs, block orders and bootstrap
  intervals are reproducible on every target.

## Install

```bash
moon add Luna-Flow/mare_mark@0.4.0
```

Then import the packages you need in your `moon.pkg`, for example:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/runner",
  "Luna-Flow/mare_mark/stats",
}
```

mare_mark needs the MoonBit toolchain 0.10 or later (`moonc` ≥ 0.10). It
depends on `moonbitlang/x` 0.5.5 and `moonbitlang/async` 0.22.4. Every package
compiles on all MoonBit targets. `runner.run` is asynchronous and runs where
`moonbitlang/async` has a runtime: native, JS and wasm (not wasm-gc).
Subprocess workers, the `replay` command and stdin/stdout reports need the
native target. `env_detect.detect` probes the host fully on native, partly on
Node.js, and falls back to environment variables elsewhere.

## Pages

The module has fourteen packages under `src`; each is documented in all three
chapters. The guides span packages.

| Part | Tutorial | API | Design |
| --- | --- | --- | --- |
| `model`: versions, protocols, environments, outcomes, events, decisions | [tutorial](tutorial/model.md) | [API](api/model.md) | [design](design/model.md) |
| `env_detect`: environment snapshots detected from the running process | [tutorial](tutorial/env_detect.md) | [API](api/env_detect.md) | [design](design/env_detect.md) |
| `generator`: seed derivation and input fingerprints | [tutorial](tutorial/generator.md) | [API](api/generator.md) | [design](design/generator.md) |
| `fixture`: input lifecycle and setup timing | [tutorial](tutorial/fixture.md) | [API](api/fixture.md) | [design](design/fixture.md) |
| `experiment`: oracles, shrinking, crossover analysis | [tutorial](tutorial/experiment.md) | [API](api/experiment.md) | [design](design/experiment.md) |
| `runner`: validation, warmup, calibration, balanced blocks | [tutorial](tutorial/runner.md) | [API](api/runner.md) | [design](design/runner.md) |
| `event`: sinks and the JSONL record | [tutorial](tutorial/event.md) | [API](api/event.md) | [design](design/event.md) |
| `ir_sink`: short constructors for the common sinks | [tutorial](tutorial/ir_sink.md) | [API](api/ir_sink.md) | [design](design/ir_sink.md) |
| `stats`: summaries, paired comparisons, bootstrap intervals, outlier views | [tutorial](tutorial/stats.md) | [API](api/stats.md) | [design](design/stats.md) |
| `ir_model`: Plot IR, plots and differential evidence | [tutorial](tutorial/ir_model.md) | [API](api/ir_model.md) | [design](design/ir_model.md) |
| `report`: JSONL to Plot IR to JSON, SVG and HTML, with paired comparisons | [tutorial](tutorial/report.md) | [API](api/report.md) | [design](design/report.md) |
| `tune`: scores, selection, Pareto fronts, seeded subsets | [tutorial](tutorial/tune.md) | [API](api/tune.md) | [design](design/tune.md) |
| `tune_gemm`: worked tuning domain, blocked matrix multiplication | [tutorial](tutorial/tune_gemm.md) | [API](api/tune_gemm.md) | [design](design/tune_gemm.md) |
| `cli`: the `mare-mark` executable, `report` with its comparison table and guarded `replay` | [tutorial](tutorial/cli.md) | [API](api/cli.md) | [design](design/cli.md) |
| Guides | [getting started](getting_started.md) | [architecture](architecture.md) | [verification](verification.md), [conventions](conventions.md) |

## Running benchmarks

- Describe a case: `runner.Case`, `runner.SingleStepCase`,
  `runner.ComparedSingleStepCase`, `runner.BenchSpec`, `runner.Implementation`
- Inputs: `fixture.Fixture`, `generator.derive_seed`,
  `generator.stable_fingerprint`
- Correctness: `experiment.ReferenceOracle`, `experiment.RelationalOracle`,
  `experiment.Shrinker`
- Protocols: `model.RunProtocol` (with `ExperimentDesign`,
  `ValidationCoverage` and `repeats_per_dataset`), `runner.validate_protocol`,
  `runner.ProtocolPreset` (`QuickCheck`, `Development`, `RegressionGate`)
- Environment: `env_detect.detect`, `env_detect.new_run_id`, or the
  `model.EnvironmentSnapshot` constructors
- Execution: `runner.run`, `runner.balanced_order`
- Identities: `model.protocol_identity`, `model.run_identity`

## Recording and reporting

- Sinks: `event.InMemorySink`, `event.JsonlSink`, `event.streaming_jsonl`,
  `event.tee`, and the short names of `ir_sink`
- Protocol records: `event.protocol_json`, `event.protocol_from_json`
- Plot IR: `ir_model.PlotDocument`, `ir_model.Plot`, `ir_model.AxisScale`,
  `ir_model.DifferentialReport`, `ir_model.ComparisonReport`
- Rendering: `report.document_from_jsonl` (plots and comparisons against a
  baseline), `report.plot_json`, `report.plot_svg`, `report.html`,
  `report.comparisons_text`, and the `mare-mark report` command

## Analysis and tuning

- Statistics: `stats.summarize`, `stats.compare_paired`,
  `stats.compare_paired_with_bootstrap`, `stats.bootstrap_interval`,
  `stats.filter_outliers`
- Crossovers: `experiment.comparator_label`,
  `experiment.crossover_from_labels`
- Tuning: `tune.score_samples`, `tune.select_best`, `tune.pareto_frontier`,
  `tune.seeded_order`, and the worked GEMM domain in `tune_gemm`

## Versioned contracts

mare_mark is pre-1.0. The versioned contracts are the protocol identity `mmkp_2` (the former `mmkp_1` is deprecated and no longer produced), the JSONL artifacts `mmka_1`, the Plot IR schema `mmks_2` (the former `mmks_1` is deprecated) and the GEMM tuning configuration `mmkts_1`; readers reject other versions. Timing
thresholds, candidate enumeration, HTML styling and private layouts are not
compatibility promises. Each design page ends with the package's boundaries.

## Where to read next

- New to benchmarking with mare_mark: read [getting started](getting_started.md),
  then the [runner tutorial](tutorial/runner.md) and the
  [env_detect tutorial](tutorial/env_detect.md). Publish and decide with the
  [report tutorial](tutorial/report.md), and read the
  [stats tutorial](tutorial/stats.md) for comparisons of your own.
- Using it in a project: keep the API pages of [`runner`](api/runner.md),
  [`stats`](api/stats.md) and [`model`](api/model.md) at hand; read the
  [fixture](tutorial/fixture.md) and [generator](tutorial/generator.md)
  tutorials for realistic inputs, and the
  [experiment tutorial](tutorial/experiment.md) for oracles and crossovers. For
  tuning, read [tune](tutorial/tune.md) and [tune_gemm](tutorial/tune_gemm.md).
- Reviewing results or contributing: read the [architecture](architecture.md)
  and the design pages, starting with [runner](design/runner.md) (experimental
  design and calibration), [stats](design/stats.md) (estimators, bootstrap
  and decision rule) and [report](design/report.md) (projection and paired
  comparisons), then [verification](verification.md).

## Validation

Recommended release checks:

```bash
moon check --target all
moon test --target native
moon test --target js
```

The [verification](verification.md) guide lists the full matrix, the artifact
smoke tests and how the examples of this manual are compiled and run.
