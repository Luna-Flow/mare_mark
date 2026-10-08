# report tutorial

This tutorial publishes benchmark results: you render a JSONL event stream as a
self-contained HTML page, see how failed validations appear, export the
machine-readable `mmks_1` JSON, and draw plots of your own. The examples are
complete tests; file writing is left to your program or to the
[`mare-mark` command](cli.md).

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```text
import {
  "Luna-Flow/mare_mark/ir_model",
  "Luna-Flow/mare_mark/report",
  "Luna-Flow/mare_mark/model",
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
no network.

## Everyday tasks

### Report a run straight from the runner

`JsonlSink` produces exactly the stream that `document_from_jsonl` reads:

```moonbit
async test "run and render" {
  let negate = @runner.Implementation::stateless("negate", "1", (x : Int) => {
    @model.OperationResult::completed(-x, ())
  })
  let plan = @runner.single_step("negate", [1, 2, 3])
    .with_immutable_input(context => context.dataset_key.scale, x => x.to_string())
    .compare([negate])
    .against_equal(x => -x, (expected, actual) => expected == actual)
    .compile()
    .unwrap()
  let sink = @event.JsonlSink::new()
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(@model.ExecutionTarget::Native, "moonc", "", "i32"),
    @model.PerformanceEnvironment::new("native", "cpu", "default", 1, "monotonic"),
    @model.ProvenanceEnvironment::new("os", "host", "now", "HEAD", "report-tutorial"),
  )
  ignore(
    @runner.run(
      plan,
      @runner.RunContext::new(environment, sink.as_sink(), 5UL, @runner.ProtocolPreset::QuickCheck.validated()),
    ),
  )
  let document = @report.document_from_jsonl(sink.to_jsonl(), target="native").unwrap()
  inspect(document.plots[0].points.length(), content="12")
  inspect(document.differential.corpus.passed, content="3")
}
```

Three scales times four blocks give twelve points, one per observation.

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

`plot_json` writes the same document as `mmks_1` JSON, which a notebook or a
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
- **Statistics in the report.** Compute comparisons with `stats` and add them
  as `Interval` plots or as text around the HTML; the renderer does not compute
  them.
- **Keep the JSONL.** The HTML is a projection that can be regenerated; the
  JSONL is the record.

## Common pitfalls

- **A stream with only calibration events.** It yields an error, because there
  is nothing to show.
- **Expecting the scale on the x axis.** The x value is the dataset index.
- **Mixing runs in one file.** Points of different runs are plotted together,
  and the last summary sets the run id.
- **Changing `artifact_version`.** Only `mmka_1` is accepted.

## Next steps

- [report API](../api/report.md) and [report design](../design/report.md).
- [ir_model API](../api/ir_model.md) for the document types.
- [event tutorial](event.md) for the stream format.
