# report API

## Purpose

`Luna-Flow/mare_mark/report` turns a JSONL event stream into a Plot IR
document and renders that document as `mmks_2` JSON, standalone SVG, a
self-contained HTML page or a plain-text table. On the way it compares every
implementation with a baseline, block by block, and decides with the
threshold and outlier policy the run recorded. All five functions are pure:
they take strings and values and return strings. Reading and writing files is
the job of the [`cli`](cli.md). The projection and the comparison rules are
derived in the [report design](../design/report.md).

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
pub fn document_from_jsonl(String, target? : String, baseline? : String) -> Result[@ir_model.PlotDocument, String]
```

`target` (default `"unknown"`) is copied into the document; the events do not
carry it. `baseline` names the implementation every other one is compared
with (see [paired comparisons](#paired-comparisons)); by default it is the
first implementation that appears in each case. Blank lines are skipped. Each
other line must be a JSON object, and its `artifact_version`, when present,
must be the string `"mmka_1"`. Lines are interpreted by their `"type"`:

| `type` | Required fields | Effect |
| --- | --- | --- |
| `observation` | `implementation` (string), `dataset_id`, `elapsed_us` (numbers) | a timing of its case, unless `valid` is `false` or `batch_sink` is not `"kept"`; `phase`, `scale` (strings) and `block_id` (number) are read when present |
| `validation` | none | counted in the capability matrix by `implementation` and `actual_kind` (`"unclassified"` when absent); a status of `invalid` or `infrastructure_failure` adds a mismatch row and, when `case` and `dataset_id` are present, removes that implementation's timings for that case and dataset |
| `validation_failure` | none | a counterexample row (minimal input, minimal fingerprint, shrink path, replay command) |
| `summary` | none | sets `run_id` and the corpus counts, and the protocol and seed of the comparisons when present; the last summary wins |
| anything else | | ignored, including `calibration` |

The document has one `Scaling` plot per case, in order of first appearance,
titled `"Benchmark observations: <case>"` (or `"Benchmark observations"` for
observations without `case`), with unit `"µs/op"` and interval kind
`"median"`. A plot contains only confirmatory timings: an observation whose
`phase` is `"confirmatory"`, or that has no `phase` because it predates the
field. Observations of any other phase are left out and counted in the plot's
note. There is one point per implementation and scale: its x is the scale and
its y the median `elapsed_us` of all confirmatory timings of that
implementation at that scale, pooled over every dataset and repetition that
shares the scale.

| Observations have | x value | `x_label` | `x_axis` |
| --- | --- | --- | --- |
| `scale` | the scale text | `scale` | `Log` when positive finite values span at least 100x; otherwise `Linear` for finite numeric values or `Categorical` |
| no `scale` | the `dataset_id` | `dataset_id (scale not recorded)` | as above |
| both kinds | the scale, or `dataset_id <n>` | `scale (dataset_id where scale is not recorded)` | `Categorical` |

The note states what a point is and, when observations were left out, how
many of which phase, for example `Excluded: 2 exploratory observations.` A
case whose observations are all excluded keeps an empty plot, so that its
note is shown. The corpus total is the sum of the four summary counts.

Errors are messages with the 1-based line number: invalid JSON, a line that is
not an object, an unsupported or non-string artifact version, an observation
without `implementation`, `dataset_id` or `elapsed_us`, a non-string `phase`
or `scale`, a non-numeric `block_id`, a summary `protocol` that
`@event.protocol_from_json` rejects (`invalid protocol at line <n>: <reason>`),
and a summary `seed` that is not the decimal text of a `UInt64`. Without a
line number: a `baseline` that names no implementation of the record, and a
stream with neither observations nor mismatches nor counterexamples.

```moonbit
test "parse a small event stream" {
  let source =
    #|{"type":"observation","case":"add","implementation":"a","dataset_id":0,"block_id":0,"phase":"exploratory","scale":"64","elapsed_us":20.0}
    #|{"type":"observation","case":"add","implementation":"a","dataset_id":0,"block_id":1,"phase":"confirmatory","scale":"64","elapsed_us":12.5}
    #|{"type":"observation","case":"add","implementation":"a","dataset_id":0,"block_id":2,"phase":"confirmatory","scale":"64","elapsed_us":12.0}
    #|{"type":"observation","case":"add","implementation":"b","dataset_id":0,"block_id":1,"phase":"confirmatory","scale":"64","elapsed_us":10.0}
    #|{"type":"observation","case":"add","implementation":"b","dataset_id":1,"block_id":1,"phase":"confirmatory","scale":"256","elapsed_us":30.0,"valid":false}
    #|{"type":"summary","run_id":"demo","passed_count":2}
  let document = @report.document_from_jsonl(source, target="native").unwrap()
  inspect(document.run_id, content="demo")
  let plot = document.plots[0]
  inspect(plot.title, content="Benchmark observations: add")
  inspect(plot.points.map(p => p.series + "@" + p.x + "=" + p.y.to_string()).join(" "), content="a@64=12.25 b@64=10")
  inspect(plot.note.has_suffix("Excluded: 1 exploratory observation."), content="true")
  inspect(document.differential.corpus.total, content="2")
  let bad = @report.document_from_jsonl("{\"artifact_version\":\"mmka_9\"}")
  inspect(bad is Err("unsupported artifact version 'mmka_9' at line 1"), content="true")
}
```

## Paired comparisons

`document_from_jsonl` also fills `PlotDocument.comparisons`: at every scale of
every case, every implementation other than the baseline is compared with the
baseline. A row is computed from the same confirmatory, valid, kept
observations that the plot uses, in these steps.

1. **Pairing.** Observations are paired by (case, scale, `block_id`). A block
   is complete when it holds exactly one observation of the baseline and one
   of the candidate; it gives the pair $(b_i, c_i)$ and the paired delta
   $d_i = c_i - b_i$. Every other block seen in either implementation is
   incomplete and counted in `blocks_incomplete`. Datasets that share a scale
   are pooled; the runner numbers blocks per scale, so their blocks never
   collide.
2. **Failed validations.** A failing validation removes the implementation's
   observations of that case and dataset before pairing, also when it is a
   measurement validation (`EveryMeasurement`). The other implementation's
   blocks of that dataset are then incomplete, so a dataset on which either
   side failed never enters a decision.
3. **Outliers.** The recorded `outlier_policy` is applied to the paired deltas
   with `@stats.filter_outliers`, never to either implementation's raw times.
   A pair is kept exactly when its delta is kept; the removed pairs are
   counted in `blocks_outliers`, and the kept ones in `blocks_used`.
4. **Enough blocks.** With fewer than 3 used blocks the row is `Unknown`.
5. **Decision.** `@stats.compare_paired_with_bootstrap` compares the used
   pairs with the recorded `practical_delta_pct`, 10000 resamples and 95 %
   confidence. The decision is that of the point estimate: with
   $r = 100\,\operatorname{med}(d)/\operatorname{med}(b)$ and threshold $t$,
   `Faster` when $r \le -t$, `Slower` when $r \ge t$, `Equivalent` otherwise
   (an exact tie is `Equivalent` for every $t$). The interval is reported next
   to it and does not change it.
6. **Interval.** `DeltaInterval` holds the bootstrap interval of the median
   delta in µs/op and as a percentage of the baseline median, the scale of
   $r$.

Each row gets its own bootstrap seed: the 64-bit FNV-1a hash of the UTF-16
code units of

```text
mare_mark/compare/v1␟<run seed in decimal>␟<case>␟<scale>␟<baseline>␟<candidate>
```

where `␟` is U+001F, the unit separator. The same record therefore gives the
same intervals on every target, and the rows of a report get different seeds
(up to a 64-bit hash collision), so adding a row does not change the interval
of another.

The settings come from the record's `summary`: `practical_delta_pct` and
`outlier_policy` from its `protocol`, the run seed from its `seed`. A record
without them (older records, hand-written streams) is compared with a 1 %
threshold, `ReportOnly` and seed 0; `ComparisonReport.protocol_recorded` and
`seed_recorded` are then `false`, and the note says that defaults were used.
The confidence, the number of resamples and the minimum of 3 blocks are fixed
by the report and named in the note.

A row that cannot be decided says why in `reason`:

| Decision | Reason |
| --- | --- |
| `Unknown` | `block_id not recorded; observations cannot be paired` |
| `Unknown` | `baseline has no confirmatory observations at this scale` |
| `Unknown` | `<n> usable blocks; at least 3 are needed` |
| `Invalid` | `baseline median is not positive; the relative delta is undefined` |
| `Invalid` | `practical_delta_pct <t> is not a finite, non-negative threshold` |
| `Invalid` | `bootstrap: <error>`, for example a paired delta that is not finite |

Confirmatory observations without `block_id` cannot be paired; the note counts
them.

```moonbit
fn observation(implementation : String, block : Int, elapsed_us : Double) -> String {
  "{\"type\":\"observation\",\"case\":\"add\",\"implementation\":\"" + implementation +
  "\",\"dataset_id\":0,\"block_id\":" + block.to_string() +
  ",\"phase\":\"confirmatory\",\"scale\":\"1024\",\"elapsed_us\":" + elapsed_us.to_string() + "}"
}

test "compare with a baseline" {
  let lines = ["{\"type\":\"summary\",\"run_id\":\"cmp\",\"seed\":\"42\"}"]
  let scalar = [10.0, 10.2, 9.9, 10.1]
  let simd = [7.0, 7.1, 6.9, 7.2]
  for block in 0..<4 {
    lines.push(observation("scalar", block, scalar[block]))
    lines.push(observation("simd", block, simd[block]))
  }
  let document = @report.document_from_jsonl(lines.join("\n"), baseline="scalar").unwrap()
  let report = document.comparisons
  let row = report.rows[0]
  inspect(row.candidate + " vs " + row.baseline + ": " + row.decision.text(), content="simd vs scalar: faster")
  inspect(row.blocks_used, content="4")
  inspect(row.estimate.unwrap().relative_delta_pct, content="-29.850746268656714")
  inspect(row.seed, content="14248938562498248866")
  inspect(report.protocol_recorded, content="false")
  inspect(report.seed_recorded, content="true")
  let unknown = @report.document_from_jsonl(lines.join("\n"), baseline="avx")
  inspect(unknown is Err("unknown baseline 'avx'; implementations in the record: scalar, simd"), content="true")
}
```

The paired deltas are $-3.0, -3.1, -3.0, -2.9$ µs/op up to rounding, their
median is $-3.0$ and the baseline median $10.05$, so
$r = 100 \cdot (-3.0)/10.05 \approx -29.85$, beyond the default threshold of
$-1\,\%$: `Faster`. The seed shown is the FNV-1a hash of the row's key with
run seed 42.

## Rendering

### `plot_json`

`plot_json` serializes a document as `mmks_2` JSON.

```mbti
pub fn plot_json(@ir_model.PlotDocument) -> String
```

The object has the keys `schema_version`, `run_id`, `target`, `plots`,
`differential` and `comparisons`. Each plot has `kind`, `title`, `unit`,
`interval_kind`, `x_axis` and `y_axis` (`"categorical"`, `"linear"` or `"log"`), `x_label`, `note`
and `points` of `x`, `y`, `series`. `differential` has `mismatches`,
`capabilities`, `counterexamples` and `corpus`. Plot kinds are written in
snake case (`scaling`, `raw_distribution`, `block_order`, `interval`,
`outlier`, `change_point`, `heatmap`, `pareto`).

`comparisons` is an object:

| Key | Value |
| --- | --- |
| `practical_delta_pct`, `confidence_pct` | numbers |
| `outlier_policy` | the policy's `text()` tag |
| `resamples`, `min_blocks` | numbers |
| `run_seed` | a decimal string |
| `protocol_source`, `seed_source` | `"record"` or `"default"` |
| `note` | the settings sentence |
| `rows` | objects with `case`, `scale`, `baseline`, `candidate`, `decision` (the `text()` name), `reason`, `estimate` (`baseline_median_us`, `candidate_median_us`, `median_delta_us`, `relative_delta_pct`, `speedup`, or `null`), `interval` (`low_us`, `high_us`, `low_pct`, `high_pct`, or `null`), `blocks_used`, `blocks_incomplete`, `blocks_outliers`, `seed` (a decimal string) |

Seeds are strings because a JSON number cannot hold every `UInt64`; numbers
in `comparisons` that are not finite are the strings `"NaN"`, `"Infinity"` and
`"-Infinity"`. The output is compact, and strings are escaped by the JSON
encoder.

```moonbit
test "plot JSON" {
  let point = @ir_model.PlotPoint::new("0", 1.0, "a")
  let plot = @ir_model.Plot::new(@ir_model.PlotKind::Scaling, "t", "µs/op", "raw", [point])
  let document = @ir_model.PlotDocument::new("r", "native", [plot])
  let json = @report.plot_json(document)
  inspect(json.has_prefix("{\"schema_version\":\"mmks_2\",\"run_id\":\"r\""), content="true")
  inspect(json.contains("\"x_axis\":\"categorical\""), content="true")
  inspect(json.contains("\"points\":[{\"x\":\"0\",\"y\":1,\"series\":\"a\"}]"), content="true")
  inspect(json.contains("\"comparisons\":{"), content="true")
}
```

### `plot_svg`

`plot_svg` renders one plot as a standalone SVG element.

```mbti
pub fn plot_svg(@ir_model.Plot) -> String
```

The SVG has a 960 × 420 view box, an accessible `<title>` and a `<desc>` that
includes the plot's note, inline styles, linear grid ticks or logarithmic ticks with bounded label density, the unit as the y-axis label, `x_label` under the x axis, and a
legend. On a categorical axis the x values are spaced evenly in order of first
appearance and at most about ten are labelled. On a linear axis they are
sorted and placed by value, and a label is drawn only when it is at least
56 px from the previous one. Every point is drawn as a circle with a tooltip
`series — x: y unit`. `Scaling`, `Interval` and `ChangePoint` plots also
connect, per series, the mean of the points at each x value. `Heatmap` plots
draw one cell per series and x category, with an opacity that grows with the
mean value. An empty plot shows "No observations". All text is XML-escaped.

```moonbit
test "plot SVG" {
  let points = [
    @ir_model.PlotPoint::new("64", 2.0, "scalar"),
    @ir_model.PlotPoint::new("128", 4.5, "scalar"),
  ]
  let plot = @ir_model.Plot::new(@ir_model.PlotKind::Scaling, "a < b", "µs/op", "median", points, x_axis=Linear, x_label="scale")
  let svg = @report.plot_svg(plot)
  inspect(svg.has_prefix("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 960 420\""), content="true")
  inspect(svg.contains("<title id=\"plot-title\">a &lt; b</title>"), content="true")
  inspect(svg.contains("<polyline"), content="true")
  inspect(svg.contains(">scale</text>"), content="true")
}
```

### `html`

`html` renders a whole document as one self-contained HTML page.

```mbti
pub fn html(@ir_model.PlotDocument) -> String
```

The page contains a header with run id, target and schema version, then the
differential report (corpus outcomes, mismatches, capability coverage matrix,
minimal counterexamples), then a "Comparisons" section when the document has
comparison rows, then one figure per plot with the plot's note in its caption.
The comparison table has one row per comparison: case, scale, baseline,
candidate, both medians in µs/op, the relative delta, the interval in
percent, the decision as a labelled tag with its reason, the blocks used,
incomplete and removed as outliers, and the row seed; the settings note is
printed above it. CSS is inline, plots are inline SVG, and there are no
scripts and no external resources, so the file can be archived or attached as
it is. The output depends only on the document.

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

### `comparisons_text`

`comparisons_text` renders the comparisons of a document as an aligned
plain-text table.

```mbti
pub fn comparisons_text(@ir_model.PlotDocument) -> String
```

The text is the line `Comparisons`, the settings note, a header line and one
line per row, with the columns of the HTML table plus the reason, separated by
at least two spaces. Missing values are `-`; deltas and interval bounds carry
an explicit sign, and numbers are rounded to three decimals. It is `""` when
the document has no comparison rows. `mare-mark report` prints it.

```moonbit
test "comparisons as text" {
  let source =
    #|{"type":"observation","case":"add","implementation":"a","dataset_id":0,"block_id":1,"scale":"64","elapsed_us":12.5}
    #|{"type":"observation","case":"add","implementation":"b","dataset_id":0,"block_id":1,"scale":"64","elapsed_us":10.0}
  let text = @report.comparisons_text(@report.document_from_jsonl(source).unwrap())
  let lines = text.split("\n").to_array()
  inspect(lines[0], content="Comparisons")
  inspect(lines[2].has_prefix("case  scale  baseline  candidate"), content="true")
  inspect(lines[3].contains("Unknown"), content="true")
  inspect(lines[3].has_suffix("1 usable block; at least 3 are needed"), content="true")
}
```

### Logarithmic axes

Scaling plots choose x and y independently. Positive finite values spanning at least 100× use base-10 logarithmic coordinates; other numeric axes remain linear, and nonnumeric x values remain categorical. Log ticks prioritize powers of ten, thinning decades for dense ranges and adding 2× and 5× ticks only when labels fit. The IR and JSON record both axis scales, and labels and notes identify log scaling.
