# MARE MARK

Reproducible benchmarking, statistical comparison, tuning, and self-contained
reports for MoonBit payloads.

`mare_mark` is an experiment harness, not a stopwatch wrapper. It keeps the
input generator, fixture lifecycle, validation oracle, timing protocol,
statistics, event schema, and report projection as explicit boundaries so a
performance result can be replayed and audited.

## 60-Second Tour

```sh
# Run the checked-in report fixture.
moon run src/cli --target native -- report \
  testdata/report/sample.jsonl report.html

# Inspect a captured validation failure without executing it.
moon run src/cli --target native -- replay \
  testdata/replay/sample.jsonl --dry-run

# Run the project checks.
moon test --target native
moon test --target js
moon fmt
```

The report command produces a self-contained HTML file with inline SVG and CSS;
it does not require a server or a network connection. `replay --dry-run` is the
safe first step for a captured worker command. Executing a replay requires the
native target and an explicit `--yes`.

## Installation

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

## Choose The Right Boundary

| Need | Start here | Why |
| --- | --- | --- |
| Describe scales, inputs, outcomes, and protocol | [`model`](./doc/en_US/package_reference.md#model) | Shared versioned vocabulary and event payloads |
| Generate deterministic inputs | [`generator`](./doc/en_US/package_reference.md#generator) | Seed derivation and stable fingerprints |
| Clone, prepare, reset, and time setup | [`fixture`](./doc/en_US/package_reference.md#fixture) | Lifecycle and setup-timing policy |
| Compare implementations | [`runner`](./doc/en_US/package_reference.md#runner) | Validation-before-timing, calibration, balanced blocks |
| Build reference or relational checks | [`experiment`](./doc/en_US/package_reference.md#experiment) | Oracles, shrinkers, and crossover decisions |
| Store or stream JSONL events | [`event`](./doc/en_US/package_reference.md#event) | In-memory, JSONL, and tee sinks |
| Summarize paired measurements | [`stats`](./doc/en_US/package_reference.md#stats) | Median deltas and deterministic bootstrap intervals |
| Render artifacts | [`report`](./doc/en_US/package_reference.md#report) | JSONL -> Plot IR -> SVG/HTML |
| Search candidate configurations | [`tune`](./doc/en_US/package_reference.md#tune) | Budgets, holdouts, scores, and Pareto fronts |
| Tune the built-in GEMM example | [`tune_gemm`](./doc/en_US/package_reference.md#tune_gemm) | Correctness, layouts, packing, workspace, and timing scope |
| Use files from a shell | [`cli`](./doc/en_US/package_reference.md#cli) | `report` and guarded `replay` commands |

The short path is `runner` + `generator` + `fixture` + `event`; add `stats`
when making a decision and `report` when publishing an artifact. `tune` and
`tune_gemm` are policy/data-model packages; they do not silently choose a
microkernel or benchmark environment for an application.

## Minimal Workflow

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/event"
  "Luna-Flow/mare_mark/generator"
  "Luna-Flow/mare_mark/model"
  "Luna-Flow/mare_mark/report"
  "Luna-Flow/mare_mark/runner"
  "Luna-Flow/mare_mark/stats"
}

let scales = [1, 2, 4]
let baseline = @runner.Implementation::stateless(
  "baseline", "1", input => @model.OperationResult::completed(sum(input), ()),
)
let candidate = @runner.Implementation::stateless(
  "candidate", "1", input => @model.OperationResult::completed(sum_fast(input), ()),
)
let plan = @runner.single_step("vector-add", scales)
  .with_immutable_input(
    ctx => make_input(ctx.dataset_key.scale),
    input => fingerprint(input),
  )
  .compare([baseline, candidate])
  .against_equal(reference, (expected, actual) => expected == actual)
  .compile()
  .unwrap()
let jsonl_sink = @event.JsonlSink::new()
let context = @runner.RunContext::new(environment, jsonl_sink.as_sink(), 42UL,
  @runner.ProtocolPreset::Development.validated())
let summary = @runner.run(plan, context)
let comparison = @stats.compare_paired(
  "baseline", "candidate", baseline_times, candidate_times,
  1.0, @model.confirmatory_interval(),
)
let document = @report.document_from_jsonl(
  jsonl_sink.to_jsonl(), target="native",
).unwrap()
let html = @report.html(document)
```

The important ordering is:

1. Build and validate an immutable plan.
2. Generate and fingerprint inputs from a seed-derived context.
3. Run oracle validation before timed blocks.
4. Emit raw observations and failure artifacts.
5. Compute summaries from preserved paired arrays.
6. Project the event stream into Plot IR and HTML.

## Measurement Contract

- `mmkp_1` identifies the protocol vocabulary, `mmka_1` replayable artifacts,
  and `mmks_1` Plot/JSON schema. Unknown versions must be rejected by readers.
- Input generation is keyed by suite, case, dataset, generator id/version, and
  seed. `generator.stable_fingerprint` is for provenance, not cryptographic
  security.
- Timed regions contain payload execution and output folding. Validation,
  calibration, fixture materialization, final sink conversion, report
  rendering, and file IO stay outside the timed closure unless a fixture's
  explicit `SetupPolicy` says otherwise.
- `BalancedBlocks(seed)` rotates implementation order by block id. Keep raw
  observations; use `stats.filter_outliers` only on an analysis view.
- Native and JS elapsed times are different populations. Compare them only as
  separately labelled runs with compatible environment snapshots.

## Event And Report Contract

The event stream is JSONL: one object per line. Observation rows carry the
`case`, `implementation`, `dataset_id`, `elapsed_us`, and `iterations` needed
for scaling plots. Validation failures additionally carry the minimized input,
fingerprint, command, arguments, timeout, and shrink path needed by replay.
Summary rows close a run and provide the run id used by Plot IR.

`report.document_from_jsonl` ignores calibration and validation rows for the
default scaling projection, but retains validation failures and corpus counters
in the differential section. Invalid observations and discarded batches are
excluded from plotted series rather than silently treated as zero.

## Documentation Map

- [English documentation](./doc/en_US/README.md)
- [简体中文文档](./doc/zh_CN/README.md)
- [日本語ドキュメント](./doc/ja_JP/README.md)
- [Getting started](./doc/en_US/getting_started.md)
- [Architecture and timing boundaries](./doc/en_US/architecture.md)
- [Package reference](./doc/en_US/package_reference.md)
- [Verification and evidence](./doc/en_US/verification.md)
- [Report fixture](./testdata/report/sample.jsonl)
- [Replay fixture](./testdata/replay/sample.jsonl)

## Development

```sh
moon test --target native
moon test --target js
moon check --target native
moon check --target js
moon fmt
moon info
```

The repository keeps application code under `src/`, documentation under
`doc/<locale>/`, and checked-in smoke inputs under `testdata/`. Generated
`pkg.generated.mbti` files are the authoritative public interface snapshots;
update prose when a public boundary changes, but do not edit generated files.

## Versioning And Scope

The current module version is `0.3.0`. The project is pre-1.0: the `model`,
`runner`, `event`, `stats`, `report`, and `tune` boundaries are intentional for
this release, while algorithm thresholds, renderer styling details, and private
implementation layouts are not compatibility promises.

## License

Apache-2.0. See [LICENSE](./LICENSE).
