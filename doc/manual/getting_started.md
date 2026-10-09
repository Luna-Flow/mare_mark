# Getting started

This guide takes you from an empty package to a validated benchmark, a
statistical decision and an HTML report in one test. It then shows the
command-line tools on the fixtures shipped with the repository.

## 1. Add the module

You need MoonBit with `moonc` 0.10 or later.

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

In the `moon.pkg` of the package that holds your benchmarks:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/env_detect",
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/runner",
  "Luna-Flow/mare_mark/stats",
  "Luna-Flow/mare_mark/report",
  "moonbitlang/async",
}
```

## 2. Benchmark, decide, report

The test below compares two ways to compute the sum of squares
$0^2 + 1^2 + \dots + (n-1)^2$: a loop and the closed form
$(n-1)n(2n-1)/6$.

```moonbit
fn squares_loop(n : Int) -> Int64 {
  let mut total = 0L
  for i in 0..<n {
    total += i.to_int64() * i.to_int64()
  }
  total
}

fn squares_formula(n : Int) -> Int64 {
  let m = n.to_int64()
  (m - 1L) * m * (2L * m - 1L) / 6L
}

async test "loop versus closed form" {
  // 1. Describe the case: inputs, implementations, oracle.
  let looped = @runner.Implementation::stateless("loop", "1", (n : Int) => {
    @model.OperationResult::completed(squares_loop(n), ())
  })
  let formula = @runner.Implementation::stateless("formula", "1", (n : Int) => {
    @model.OperationResult::completed(squares_formula(n), ())
  })
  let plan = @runner.single_step("sum-of-squares", [100, 10000])
    .with_immutable_input(context => context.dataset_key.scale, n => n.to_string())
    .compare([looped, formula])
    .against_equal(squares_loop, (expected, actual) => expected == actual)
    .compile()
    .unwrap()
  // 2. Run it with a seed, the detected environment and two sinks.
  let memory = @event.InMemorySink::new()
  let record = @event.JsonlSink::new()
  let environment = @env_detect.detect(compiler_flags="release", dtype_abi="i64", concurrency=1).snapshot
  let summary = @runner.run(
    plan,
    @runner.RunContext::new(
      environment,
      @event.tee(memory.as_sink(), record.as_sink()),
      42UL,
      @runner.ProtocolPreset::Development.validated(),
    ),
  )
  inspect(summary.passed_count, content="4")
  inspect(summary.failed_count, content="0")
  // 3. Decide on the larger dataset with paired confirmatory blocks.
  let baseline = memory.observations
    .filter(o => o.dataset_id == 1 && o.implementation_id == "loop" && o.phase is Confirmatory)
    .map(o => o.raw_elapsed_us)
  let candidate = memory.observations
    .filter(o => o.dataset_id == 1 && o.implementation_id == "formula" && o.phase is Confirmatory)
    .map(o => o.raw_elapsed_us)
  let comparison = @stats.compare_paired_with_bootstrap(
    "loop", "formula", baseline, candidate, 5.0, @model.confirmatory_interval(), 42UL, 2000, 95.0,
  ).unwrap()
  inspect(comparison.valid_samples, content="10")
  // 4. Render the record; the report makes the same comparison at every scale.
  let document = @report.document_from_jsonl(record.to_jsonl(), target="native", baseline="loop").unwrap()
  inspect(document.comparisons.rows.length(), content="2")
  inspect(document.comparisons.rows.all(row => row.blocks_used == 10), content="true")
  inspect(@report.html(document).has_prefix("<!doctype html>"), content="true")
}
```

What happened:

1. `against_equal` attached the loop as the reference oracle. Both
   implementations were validated on both scales before any timing (four
   passed validations).
2. `env_detect.detect` described the machine (target, runtime, CPU and
   cores, OS, host, time, revision, a fresh run id); the test adds what the
   process cannot know: the build flags, the numeric ABI and that the
   benchmark runs one operation at a time.
3. `Development` warmed every implementation up, calibrated a batch size per
   implementation, then ran 3 exploratory and 10 confirmatory blocks per
   scale on one dataset, rotating the order of the two implementations.
4. The confirmatory blocks are paired by position (block $i$ of the loop with
   block $i$ of the formula). `comparison.decision` and
   `comparison.speedup` depend on your machine; the formula is expected to be
   `Faster`.
5. The JSONL record (`record.to_jsonl()`) holds every event, and its summary
   the protocol, the seed and the environment. `document_from_jsonl` pairs
   the confirmatory blocks again, at both scales, and decides with the
   protocol's 1 % threshold; the HTML shows these decisions in a
   "Comparisons" table above the plots. Save the record next to the HTML.

Run it with `moon test --target native`. The test also runs on `js` and
`wasm`.

## 3. Use the command line

From a checkout of the repository:

```sh
moon run src/cli --target native -- report testdata/report/compare.jsonl report.html
moon run src/cli --target native -- report --baseline simd testdata/report/compare.jsonl report.html
moon run src/cli --target native -- report - - < testdata/report/sample.jsonl > report.html
moon run src/cli --target native -- replay testdata/replay/sample.jsonl --dry-run
```

`report` writes a self-contained HTML file and prints the comparison of every
implementation with the baseline (the first one, or the one named by
`--baseline`). `replay --dry-run` prints the command recorded in a validation
failure; add `--yes` instead of `--dry-run` to execute it. See the
[cli tutorial](tutorial/cli.md).

## Common first mistakes

- Doing setup work (allocation, parsing, copying) inside the implementation
  function, where it is timed. Put it in a fixture.
- Comparing arrays from different blocks, phases, datasets or targets.
- Treating `Unsupported`, a timeout or a validation failure as a number.
- Executing a replay artifact without reading it with `--dry-run` first.
- Reusing one hand-written environment for every run: `summary.run_id`
  contains its provenance run id and timestamp, so the runs then share an id.
  `@env_detect.detect` makes a fresh one each time.
- Leaving `concurrency` to `detect`: it is the benchmark's own parallelism and
  stays `0` (unknown) unless you pass it.

## Where to go next

- [runner tutorial](tutorial/runner.md) for fixtures, sequences, shrinking,
  several datasets per scale and protocols.
- [env_detect tutorial](tutorial/env_detect.md) for what is detected and how
  to override it.
- [report tutorial](tutorial/report.md) for plots and comparisons.
- [stats tutorial](tutorial/stats.md) for decisions and intervals.
- [architecture](architecture.md) for how the packages fit together.
