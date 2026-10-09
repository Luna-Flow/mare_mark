# report tutorial

This tutorial publishes benchmark results: you render a JSONL event stream as a
self-contained HTML page, compare implementations against a baseline, see how
failed validations appear, export the machine-readable `mmks_2` JSON, and draw
plots of your own. The examples are
complete tests; file writing is left to your program or to the
[`mare-mark` command](cli.md).

| I want to | Use |
| --- | --- |
| render a JSONL stream as HTML | `@report.document_from_jsonl` and `@report.html` |
| report a run without a file | an in-memory JSONL sink, then the two functions above |
| decide which implementation is faster | the `comparisons` of the document, with `baseline=` |
| print the decisions in a terminal or CI log | `@report.comparisons_text` |
| export machine-readable results | `@report.plot_json` (`mmks_2`) |
| draw one plot as SVG | `@report.plot_svg` |
| publish numbers that did not come from a run | a `PlotDocument` built with `ir_model` |

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/ir_model",
  "Luna-Flow/mare_mark/report",
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/env_detect",
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/runner",
  "moonbitlang/async",
}
```

```moonbit
test "JSONL to HTML" {
  let events =
    #|{"type":"observation","case":"add","implementation":"baseline","dataset_id":0,"elapsed_us":12.5}
    #|{"type":"observation","case":"add","implementation":"candidate","dataset_id":0,"elapsed_us":10.2}
    #|{"type":"summary","run_id":"first-report"}
  let document = @report.document_from_jsonl(events, target="native").unwrap()
  let page = @report.html(document)
  inspect(page.contains("Run first-report"), content="true")
  inspect(page.contains("<svg"), content="true")
}
```

Save `page` as `report.html` and open it in a browser; it needs no server and
no network. These hand-written lines have no `phase`, `scale` or `block_id`;
the report treats them as confirmatory timings, places them by `dataset_id`,
and cannot pair them. Records written by the runner carry all three.

## Everyday tasks

### Report a run straight from the runner

`JsonlSink` produces exactly the stream that `document_from_jsonl` reads:

```moonbit
async fn negation_record() -> String {
  let negate = @runner.Implementation::stateless("negate", "1", (x : Int) => {
    @model.OperationResult::completed(-x, ())
  })
  let subtract = @runner.Implementation::stateless("subtract", "1", (x : Int) => {
    @model.OperationResult::completed(0 - x, ())
  })
  let plan = @runner.single_step("negate", [1, 2, 3])
    .with_immutable_input(context => context.dataset_key.scale, x => x.to_string())
    .compare([negate, subtract])
    .against_equal(x => -x, (expected, actual) => expected == actual)
    .compile()
    .unwrap()
  let sink = @event.JsonlSink::new()
  let environment = @env_detect.detect(compiler_flags="debug", dtype_abi="i32", concurrency=1).snapshot
  ignore(
    @runner.run(
      plan,
      @runner.RunContext::new(environment, sink.as_sink(), 5UL, @runner.ProtocolPreset::QuickCheck.validated()),
    ),
  )
  sink.to_jsonl()
}

async test "run and render" {
  let document = @report.document_from_jsonl(negation_record(), target="native").unwrap()
  let plot = document.plots[0]
  inspect(plot.title, content="Benchmark observations: negate")
  inspect(plot.points.length(), content="6")
  inspect(plot.x_label, content="dataset_id (scale not recorded)")
  inspect(document.differential.corpus.passed, content="6")
}
```

`QuickCheck` measures one exploratory and three confirmatory blocks per scale.
The plot keeps only the confirmatory ones and shows one point per
implementation and scale, the median of its three blocks: three scales and two
implementations give six points. The `single_step` builder records no scale
text, so the x axis shows the `dataset_id`; build the case with
`BenchSpec::advanced` and a `scale_text` function to put the scales
themselves on the axis.

### Compare implementations against a baseline

The same document holds the paired comparison of every implementation with a
baseline at every scale. The runner records the protocol and the seed in the
summary, so the report decides with the run's own threshold and outlier
policy:

```moonbit
async test "decide against a baseline" {
  let document = @report.document_from_jsonl(negation_record(), baseline="negate").unwrap()
  let comparisons = document.comparisons
  inspect(comparisons.rows.length(), content="3")
  inspect(comparisons.rows.all(row => row.candidate == "subtract" && row.blocks_used == 3), content="true")
  inspect(comparisons.protocol_recorded && comparisons.seed_recorded, content="true")
  inspect(comparisons.practical_delta_pct, content="1")
  let table = @report.comparisons_text(document)
  inspect(table.has_prefix("Comparisons\nDecision threshold ±1 % and outlier policy report_only"), content="true")
}
```

Each row pairs the two implementations block by block, so the drift of the
machine between blocks cancels, and decides on the median paired delta in
percent of the baseline: `Faster` or `Slower` when it is at least the
threshold, `Equivalent` otherwise, `Unknown` with fewer than three usable
blocks. Read the interval next to it: with three blocks it spans the whole
range of the deltas. The decisions themselves depend on your machine, which is
why the test does not show them. Without `baseline=` the first implementation
of each case is the baseline.

### See what happens to a wrong implementation

A failing validation removes the implementation's points for that dataset and
adds a mismatch row:

```moonbit
test "failures hide series and show mismatches" {
  let events =
    #|{"type":"observation","case":"add","implementation":"good","dataset_id":0,"elapsed_us":12.0}
    #|{"type":"observation","case":"add","implementation":"fast-but-wrong","dataset_id":0,"elapsed_us":1.0}
    #|{"type":"validation","status":"invalid","case":"add","implementation":"fast-but-wrong","dataset_id":0,"operation":"add","operands":["1","2"],"expected":"3","actual":"4","actual_kind":"value"}
    #|{"type":"summary","run_id":"mismatch","passed_count":1,"failed_count":1}
  let document = @report.document_from_jsonl(events).unwrap()
  inspect(document.plots[0].points.length(), content="1")
  inspect(document.plots[0].points[0].series, content="good")
  inspect(document.differential.mismatches[0].actual, content="4")
  inspect(@report.html(document).contains("Mismatches"), content="true")
}
```

### Export JSON for other tools

`plot_json` writes the same document as `mmks_2` JSON, which a notebook or a
dashboard can read without parsing HTML:

```moonbit
test "machine-readable output" {
  let events =
    #|{"type":"observation","case":"add","implementation":"a","dataset_id":0,"elapsed_us":2.5}
  let json = @report.plot_json(@report.document_from_jsonl(events).unwrap())
  inspect(json.contains("\"kind\":\"scaling\""), content="true")
  inspect(json.contains("\"y\":2.5"), content="true")
}
```

### Draw a plot of your own

Plot IR is plain data. Build a document by hand, for example from a tuning
sweep, and render it with the same functions:

```moonbit
test "a hand-made heatmap" {
  let cells = [
    @ir_model.PlotPoint::new("mc=32", 3.1, "kc=32"),
    @ir_model.PlotPoint::new("mc=64", 2.7, "kc=32"),
    @ir_model.PlotPoint::new("mc=32", 2.9, "kc=64"),
    @ir_model.PlotPoint::new("mc=64", 2.4, "kc=64"),
  ]
  let plot = @ir_model.Plot::new(@ir_model.PlotKind::Heatmap, "Blocking sweep", "µs/op", "median", cells)
  let svg = @report.plot_svg(plot)
  inspect(svg.contains("<rect"), content="true")
  let document = @ir_model.PlotDocument::new("sweep", "native", [plot])
  inspect(@report.html(document).contains("Blocking sweep"), content="true")
}
```

## Going further

- **Files and pipes.** `mare-mark report events.jsonl report.html` and
  `mare-mark report - -` do the reading and writing for you; see the
  [cli tutorial](cli.md).
- **Your own statistics.** The report compares against one baseline with the
  recorded settings. For other questions (all pairs, another threshold, a
  subset of datasets), compute comparisons with `stats` and add them as
  `Interval` plots; see the [ir_model tutorial](ir_model.md).
- **Keep the JSONL.** The HTML is a projection that can be regenerated; the
  JSONL is the record.

## Common pitfalls

- **A stream with only calibration events.** It yields an error, because there
  is nothing to show.
- **Expecting the scale on the x axis with `single_step`.** That builder
  records no scale text, so the report uses `dataset_id`; use
  `BenchSpec::advanced` with a `scale_text` function.
- **Looking for exploratory blocks in the plot.** Only confirmatory
  observations are plotted and compared; the plot's note says how many were
  left out.
- **Mixing runs in one file.** Observations of different runs are pooled and
  their blocks paired with each other, and the last summary sets the run id,
  the protocol and the seed. Render each run's record separately.
- **Reading a decision without its row.** Check `blocks_used`, the
  incomplete and outlier counts, and the interval; a decision on three blocks
  is a weak one.
- **Changing `artifact_version`.** Only `mmka_1` is accepted.

## Next steps

- [report API](../api/report.md) and [report design](../design/report.md).
- [ir_model API](../api/ir_model.md) for the document types.
- [event tutorial](event.md) for the stream format.

### Logarithmic axes

Scaling plots choose x and y independently. Positive finite values spanning at least 100× use base-10 logarithmic coordinates; other numeric axes remain linear, and nonnumeric x values remain categorical. Log ticks prioritize powers of ten, thinning decades for dense ranges and adding 2× and 5× ticks only when labels fit. The IR and JSON record both axis scales, and labels and notes identify log scaling.
