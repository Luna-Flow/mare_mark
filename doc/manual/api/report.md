# report API

## Purpose

`Luna-Flow/mare_mark/report` turns a JSONL event stream into a Plot IR
document and renders that document as `mmks_2` JSON, standalone SVG or a
self-contained HTML page. All four functions are pure: they take strings and
values and return strings. Reading and writing files is the job of the
[`cli`](cli.md). The projection rules are explained in the
[report design](../design/report.md).

Source: [`src/report/report.mbt`](../../../src/report/report.mbt).

## Importing

Add the packages to the `moon.pkg` of the package that uses them:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/ir_model",
  "Luna-Flow/mare_mark/report",
}
```

The examples on this page call them through their default aliases (`@ir_model`,
`@report`).

## Parsing events

### `document_from_jsonl`

`document_from_jsonl` parses a JSONL event stream into a `PlotDocument`.

```mbti
pub fn document_from_jsonl(String, target? : String) -> Result[@ir_model.PlotDocument, String]
```

`target` (default `"unknown"`) is copied into the document; the events do not
carry it. Blank lines are skipped. Each other line must be a JSON object, and
its `artifact_version`, when present, must be the string `"mmka_1"`. Lines are
interpreted by their `"type"`:

| `type` | Required fields | Effect |
| --- | --- | --- |
| `observation` | `implementation` (string), `dataset_id`, `elapsed_us` (numbers) | a plot point (x = `dataset_id`, y = `elapsed_us`, series = `implementation`), unless `valid` is `false` or `batch_sink` is not `"kept"` |
| `validation` | none | counted in the capability matrix by `implementation` and `actual_kind` (`"unclassified"` when absent); a status of `invalid` or `infrastructure_failure` adds a mismatch row and, when `case` and `dataset_id` are present, removes that implementation's points for that case and dataset |
| `validation_failure` | none | a counterexample row (minimal input, minimal fingerprint, shrink path, replay command) |
| `summary` | none | sets `run_id` and the corpus counts; the last summary wins |
| anything else | | ignored, including `calibration` |

The document has one `Scaling` plot titled `"Benchmark observations"` with
unit `"µs/op"` and interval kind `"raw"`, or no plot when no point survives.
Exploratory and confirmatory observations are plotted together. The corpus
total is the sum of the four summary counts.

Errors are messages with the 1-based line number: invalid JSON, a line that is
not an object, an unsupported or non-string artifact version, an observation
without `implementation`, `dataset_id` or `elapsed_us`, and a stream with
neither points nor mismatches nor counterexamples.

```moonbit
test "parse a small event stream" {
  let source =
    #|{"type":"observation","case":"add","implementation":"a","dataset_id":0,"elapsed_us":12.5}
    #|{"type":"observation","case":"add","implementation":"b","dataset_id":0,"elapsed_us":10.0}
    #|{"type":"observation","case":"add","implementation":"b","dataset_id":1,"elapsed_us":30.0,"valid":false}
    #|{"type":"summary","run_id":"demo","passed_count":2}
  let document = @report.document_from_jsonl(source, target="native").unwrap()
  inspect(document.run_id, content="demo")
  inspect(document.plots[0].points.length(), content="2")
  inspect(document.differential.corpus.total, content="2")
  let bad = @report.document_from_jsonl("{\"artifact_version\":\"mmka_9\"}")
  inspect(bad is Err("unsupported artifact version 'mmka_9' at line 1"), content="true")
}
```

## Rendering

### `plot_json`

`plot_json` serializes a document as `mmks_2` JSON.

```mbti
pub fn plot_json(@ir_model.PlotDocument) -> String
```

The object has the keys `schema_version`, `run_id`, `target`, `plots` (each
with `kind`, `title`, `unit`, `interval_kind`, `x_axis`, `y_axis`, `x_label`,
`note` and `points` of `x`, `y`, `series`) and `differential` (`mismatches`, `capabilities`,
`counterexamples`, `corpus`). Plot kinds are written in snake case
(`scaling`, `raw_distribution`, `block_order`, `interval`, `outlier`,
`change_point`, `heatmap`, `pareto`). The output is compact, and strings are
escaped by the JSON encoder.

```moonbit
test "plot JSON" {
  let point = @ir_model.PlotPoint::new("0", 1.0, "a")
  let plot = @ir_model.Plot::new(@ir_model.PlotKind::Scaling, "t", "µs/op", "raw", [point])
  let document = @ir_model.PlotDocument::new("r", "native", [plot])
  let json = @report.plot_json(document)
  inspect(json.has_prefix("{\"schema_version\":\"mmks_2\",\"run_id\":\"r\""), content="true")
  inspect(json.contains("\"points\":[{\"x\":\"0\",\"y\":1,\"series\":\"a\"}]"), content="true")
}
```

### `plot_svg`

`plot_svg` renders one plot as a standalone SVG element.

```mbti
pub fn plot_svg(@ir_model.Plot) -> String
```

The SVG has a 960 × 420 view box, an accessible `<title>` and `<desc>`,
inline styles, linear grid ticks or, on logarithmic axes, a label at every
power of ten (every k-th one when decades are dense) with 2× and 5× ticks when
space allows, at most about ten x labels, and a legend. Every point is drawn as a circle with a tooltip
`series — x: y unit`. `Scaling`, `Interval` and `ChangePoint` plots also
connect, per series, the mean of the points at each x category. `Heatmap`
plots draw one cell per series and x category, with an opacity that grows with
the mean value. An empty plot shows "No observations". All text is
XML-escaped.

```moonbit
test "plot SVG" {
  let points = [
    @ir_model.PlotPoint::new("64", 2.0, "scalar"),
    @ir_model.PlotPoint::new("128", 4.5, "scalar"),
  ]
  let plot = @ir_model.Plot::new(@ir_model.PlotKind::Scaling, "a < b", "µs/op", "raw", points)
  let svg = @report.plot_svg(plot)
  inspect(svg.has_prefix("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 960 420\""), content="true")
  inspect(svg.contains("<title id=\"plot-title\">a &lt; b</title>"), content="true")
  inspect(svg.contains("<polyline"), content="true")
}
```

### `html`

`html` renders a whole document as one self-contained HTML page.

```mbti
pub fn html(@ir_model.PlotDocument) -> String
```

The page contains a header with run id, target and schema version, then the
differential report (corpus outcomes, mismatches, capability coverage matrix,
minimal counterexamples), then one figure per plot. CSS is inline, plots are
inline SVG, and there are no scripts and no external resources, so the file can
be archived or attached as it is. The output depends only on the document.

```moonbit
test "self-contained HTML" {
  let source =
    #|{"type":"observation","case":"add","implementation":"a","dataset_id":0,"elapsed_us":12.5}
    #|{"type":"summary","run_id":"demo"}
  let page = @report.html(@report.document_from_jsonl(source).unwrap())
  inspect(page.has_prefix("<!doctype html>"), content="true")
  inspect(page.contains("<title>mare_mark · demo</title>"), content="true")
  inspect(page.contains("<script"), content="false")
}
```
