# mare_mark

Reproducible benchmarking, statistical comparison, tuning and self-contained
reports for MoonBit.

`mare_mark` is an experiment harness, not a stopwatch wrapper. It validates
every implementation against an oracle before timing it, measures in
calibrated batches with a balanced, seeded order, keeps every raw observation
in an append-only JSONL record, decides with paired robust statistics and a
seeded bootstrap, and renders reports that need no server. A result can be
replayed, re-analysed and audited from its record.

## Installation

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

Requires MoonBit with `moonc` 0.10 or later.

## Example

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/runner",
  "Luna-Flow/mare_mark/report",
  "moonbitlang/async",
}
```

```moonbit
async test "loop versus closed form" {
  let looped = @runner.Implementation::stateless("loop", "1", (n : Int) => {
    let mut total = 0
    for i in 0..<n {
      total += i
    }
    @model.OperationResult::completed(total, ())
  })
  let formula = @runner.Implementation::stateless("formula", "1", (n : Int) => {
    @model.OperationResult::completed(n * (n - 1) / 2, ())
  })
  let plan = @runner.single_step("triangle", [1000, 100000])
    .with_immutable_input(context => context.dataset_key.scale, n => n.to_string())
    .compare([looped, formula])
    .against_equal(n => n * (n - 1) / 2, (expected, actual) => expected == actual)
    .compile()
    .unwrap()
  let record = @event.JsonlSink::new()
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(@model.ExecutionTarget::Native, "moonc 0.10", "release", "i32"),
    @model.PerformanceEnvironment::new("native", "my-cpu", "default", 1, "monotonic"),
    @model.ProvenanceEnvironment::new("my-os", "my-host", "2026-10-08T12:00:00Z", "HEAD", "readme"),
  )
  let summary = @runner.run(
    plan,
    @runner.RunContext::new(environment, record.as_sink(), 42UL, @runner.ProtocolPreset::QuickCheck.validated()),
  )
  inspect(summary.passed_count, content="4")
  let html = @report.html(@report.document_from_jsonl(record.to_jsonl(), target="native").unwrap())
  inspect(html.has_prefix("<!doctype html>"), content="true")
}
```

Both implementations are validated on both scales before timing; the JSONL
record holds every observation, and `@stats.compare_paired` turns the paired
confirmatory blocks into a decision. The command-line tool renders records and
replays failures:

```sh
moon run src/cli --target native -- report testdata/report/sample.jsonl report.html
moon run src/cli --target native -- replay testdata/replay/sample.jsonl --dry-run
```

## Packages

| Package | Role |
| --- | --- |
| [`model`](doc/manual/api/model.md) | shared vocabulary: versions, protocols, environments, outcomes, events, decisions |
| [`generator`](doc/manual/api/generator.md) | seed derivation and input fingerprints |
| [`fixture`](doc/manual/api/fixture.md) | input lifecycle and setup timing |
| [`experiment`](doc/manual/api/experiment.md) | oracles, shrinking, crossover analysis |
| [`runner`](doc/manual/api/runner.md) | validation, warmup, calibration, balanced blocks, raw events |
| [`event`](doc/manual/api/event.md) | sinks and the JSONL record |
| [`ir_sink`](doc/manual/api/ir_sink.md) | short constructors for the common sinks |
| [`stats`](doc/manual/api/stats.md) | summaries, paired comparisons, bootstrap intervals, outlier views |
| [`ir_model`](doc/manual/api/ir_model.md) | Plot IR |
| [`report`](doc/manual/api/report.md) | JSONL to JSON, SVG and self-contained HTML |
| [`tune`](doc/manual/api/tune.md) | tuning policy: scores, practical ties, Pareto fronts, seeded subsets |
| [`tune_gemm`](doc/manual/api/tune_gemm.md) | worked tuning domain: blocked matrix multiplication |
| [`cli`](doc/manual/api/cli.md) | the `mare-mark` executable: `report` and guarded `replay` |

All packages build on every target. `runner.run` is asynchronous and runs on
native, JS and wasm; subprocess workers and `replay` need native.

## Documentation

The manual is published at <https://lunaflow.cn/en/mare_mark/> in English,
Chinese and Japanese. Its source is [`doc/manual/index.md`](doc/manual/index.md):
an API page, a tutorial and a design page for every package, plus
[getting started](doc/manual/getting_started.md),
[architecture](doc/manual/architecture.md) and
[verification](doc/manual/verification.md).

## Contributing

Run `moon fmt`, `moon info`, `moon check --target all`, and
`moon test --target native` and `--target js` before a pull request; the
[verification guide](doc/manual/verification.md) lists the full matrix and the
smoke tests. Use Conventional Commits. `pkg.generated.mbti` files are generated:
update them with `moon info`, never by hand, and update the API pages when they
change. Agent-specific notes are in [AGENTS.md](AGENTS.md).

## License

Apache-2.0. See [LICENSE](LICENSE).
