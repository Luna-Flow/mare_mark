# Getting Started

This guide takes a small case from a checked-in JSONL artifact to a typed
benchmark plan and back to a report. For package ownership, see the
[package reference](./package_reference.md).

## 1. Check the toolchain

```sh
moon --version
moon test --target native
moon test --target js
```

`mare_mark` is a MoonBit module. Native is required for subprocess workers and
replay; the pure model, stats, report, and most runner paths are also tested on
JS.

## 2. Render the fixture

```sh
moon run src/cli --target native -- report \
  testdata/report/sample.jsonl report.html
```

Open `report.html` locally. The renderer emits inline SVG/CSS, so the artifact
is portable and reviewable without a running service. To stream a report to
stdout:

```sh
moon run src/cli --target native -- report - - < testdata/report/sample.jsonl
```

## 3. Inspect a replay artifact

```sh
moon run src/cli --target native -- replay \
  testdata/replay/sample.jsonl --dry-run
```

Dry-run prints the recorded command, arguments, and timeout. Only run an
artifact you trust, and make execution explicit:

```sh
moon run src/cli --target native -- replay \
  testdata/replay/sample.jsonl --yes
```

## 4. Define a case

Use a deterministic input callback. The single-step builder creates an
immutable fixture; advanced cases can use `Fixture::new` when cloning,
preparation, reset, or setup timing must be explicit. Keep the payload closure
small; validation and output conversion are runner responsibilities.

```moonbit nocheck
let baseline = @runner.Implementation::stateless(
  "baseline", "1", input => @model.OperationResult::completed(run_a(input), ()),
)
let candidate = @runner.Implementation::stateless(
  "candidate", "1", input => @model.OperationResult::completed(run_b(input), ()),
)
```

## 5. Add an oracle and compile

Reference or relational checks should be attached before timing. Compilation
rejects empty cases, duplicate ids, missing sinks/oracles, invalid scales, and
invalid sequence lengths.

```moonbit nocheck
let plan = @runner.single_step("vector-add", [64, 256, 1024])
  .with_immutable_input(
    ctx => make_input(ctx.dataset_key.scale),
    input => @generator.stable_fingerprint(serialize(input)),
  )
  .compare([baseline, candidate])
  .against_equal(reference, (expected, actual) => expected == actual)
  .compile()
  .unwrap()
```

## 6. Run, analyze, publish

```moonbit nocheck
let validated = @runner.ProtocolPreset::Development.validated()
let sink = @event.JsonlSink::new()
let context = @runner.RunContext::new(environment, sink.as_sink(), 42UL, validated)
let run_result = @runner.run(plan, context)
let comparison = @stats.compare_paired(
  "baseline", "candidate", baseline_us, candidate_us,
  1.0, @model.confirmatory_interval(),
)
let document = @report.document_from_jsonl(sink.to_jsonl(), target="native")
  .unwrap()
let html = @report.html(document)
```

Keep the JSONL beside the HTML. The JSONL is the audit record; HTML is a
projection that can be regenerated after renderer changes.

## Common first mistakes

- Timing fixture allocation or report rendering by placing them inside the
  payload closure.
- Comparing arrays with different block/repetition alignment.
- Treating `Unsupported`, timeout, or validation failure as a numeric zero.
- Running a native replay without inspecting it with `--dry-run` first.
- Mixing native and JS observations in one statistical population.
