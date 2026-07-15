///|
fn kind_name(kind : @ir.PlotKind) -> String {
  match kind {
    @ir.PlotKind::Scaling => "scaling"
    @ir.PlotKind::RawDistribution => "raw_distribution"
    @ir.PlotKind::BlockOrder => "block_order"
    @ir.PlotKind::Interval => "interval"
    @ir.PlotKind::Outlier => "outlier"
    @ir.PlotKind::ChangePoint => "change_point"
    @ir.PlotKind::Heatmap => "heatmap"
    @ir.PlotKind::Pareto => "pareto"
  }
}

///|
fn escape_xml(value : String) -> String {
  value
  .replace(old="&", new="&amp;")
  .replace(old="<", new="&lt;")
  .replace(old=">", new="&gt;")
  .replace(old="\"", new="&quot;")
  .replace(old="'", new="&apos;")
}

///|
fn string_index(values : Array[String], value : String) -> Int {
  for index = 0; index < values.length(); index = index + 1 {
    if values[index] == value {
      return index
    }
  }
  -1
}

///|
fn unique_x_values(plot : @ir.Plot) -> Array[String] {
  let values = []
  for point in plot.points {
    if string_index(values, point.x) < 0 {
      values.push(point.x)
    }
  }
  values
}

///|
fn unique_series(plot : @ir.Plot) -> Array[String] {
  let values = []
  for point in plot.points {
    let name = if point.series == "" { "value" } else { point.series }
    if string_index(values, name) < 0 {
      values.push(name)
    }
  }
  values
}

///|
fn y_bounds(plot : @ir.Plot) -> (Double, Double) {
  if plot.points.is_empty() {
    (0.0, 1.0)
  } else {
    let mut low = plot.points[0].y
    let mut high = plot.points[0].y
    for point in plot.points {
      low = low.min(point.y)
      high = high.max(point.y)
    }
    if low == high {
      let padding = low.abs().max(1.0) * 0.1
      (low - padding, high + padding)
    } else {
      let padding = (high - low) * 0.08
      (low - padding, high + padding)
    }
  }
}

///|
fn x_position(index : Int, count : Int) -> Double {
  if count <= 1 {
    478.0
  } else {
    76.0 + index.to_double() * 804.0 / (count - 1).to_double()
  }
}

///|
fn y_position(value : Double, low : Double, high : Double) -> Double {
  354.0 - (value - low) * 252.0 / (high - low)
}

///|
fn format_number(value : Double) -> String {
  ((value * 1000.0).round() / 1000.0).to_string()
}

///|
fn series_color(index : Int) -> String {
  let colors = [
    "#2563eb", "#dc2626", "#059669", "#7c3aed", "#d97706", "#0891b2", "#db2777",
    "#4f46e5",
  ]
  colors[index % colors.length()]
}

///|
fn average_at(plot : @ir.Plot, x : String, series : String) -> Double? {
  let mut sum = 0.0
  let mut count = 0
  for point in plot.points {
    let point_series = if point.series == "" { "value" } else { point.series }
    if point.x == x && point_series == series {
      sum += point.y
      count += 1
    }
  }
  if count == 0 {
    None
  } else {
    Some(sum / count.to_double())
  }
}

///|
fn renders_line(kind : @ir.PlotKind) -> Bool {
  match kind {
    @ir.PlotKind::Scaling
    | @ir.PlotKind::Interval
    | @ir.PlotKind::ChangePoint => true
    _ => false
  }
}

///|
fn svg_axes(
  plot : @ir.Plot,
  x_values : Array[String],
  low : Double,
  high : Double,
) -> String {
  let mut body = ""
  for tick = 0; tick <= 4; tick = tick + 1 {
    let y = 102.0 + tick.to_double() * 63.0
    let value = high - (high - low) * tick.to_double() / 4.0
    body += "<line class=\"grid\" x1=\"76\" y1=\"" +
      y.to_string() +
      "\" x2=\"880\" y2=\"" +
      y.to_string() +
      "\"/><text class=\"tick\" x=\"66\" y=\"" +
      (y + 4.0).to_string() +
      "\" text-anchor=\"end\">" +
      escape_xml(format_number(value)) +
      "</text>"
  }
  body += "<line class=\"axis\" x1=\"76\" y1=\"102\" x2=\"76\" y2=\"354\"/>"
  body += "<line class=\"axis\" x1=\"76\" y1=\"354\" x2=\"880\" y2=\"354\"/>"
  let stride = ((x_values.length() + 9) / 10).max(1)
  for index = 0; index < x_values.length(); index = index + 1 {
    if index % stride == 0 || index == x_values.length() - 1 {
      let x = x_position(index, x_values.length())
      body += "<line class=\"axis\" x1=\"" +
        x.to_string() +
        "\" y1=\"354\" x2=\"" +
        x.to_string() +
        "\" y2=\"360\"/><text class=\"tick\" x=\"" +
        x.to_string() +
        "\" y=\"378\" text-anchor=\"middle\">" +
        escape_xml(x_values[index]) +
        "</text>"
    }
  }
  body += "<text class=\"axis-label\" x=\"22\" y=\"228\" text-anchor=\"middle\" transform=\"rotate(-90 22 228)\">" +
    escape_xml(plot.unit) +
    "</text>"
  body
}

///|
fn svg_legend(series_values : Array[String]) -> String {
  let mut body = "<g aria-label=\"Legend\">"
  for index = 0; index < series_values.length(); index = index + 1 {
    let x = 76 + index % 4 * 200
    let y = 78 + index / 4 * 20
    body += "<circle cx=\"" +
      x.to_string() +
      "\" cy=\"" +
      y.to_string() +
      "\" r=\"5\" fill=\"" +
      series_color(index) +
      "\"/><text class=\"legend\" x=\"" +
      (x + 10).to_string() +
      "\" y=\"" +
      (y + 4).to_string() +
      "\">" +
      escape_xml(series_values[index]) +
      "</text>"
  }
  body + "</g>"
}

///|
fn svg_series_plot(
  plot : @ir.Plot,
  x_values : Array[String],
  series_values : Array[String],
  low : Double,
  high : Double,
) -> String {
  let mut body = ""
  if renders_line(plot.kind) {
    for series_index = 0
        series_index < series_values.length()
        series_index = series_index + 1 {
      let coordinates = []
      for x_index = 0; x_index < x_values.length(); x_index = x_index + 1 {
        match average_at(plot, x_values[x_index], series_values[series_index]) {
          Some(value) =>
            coordinates.push(
              x_position(x_index, x_values.length()).to_string() +
              "," +
              y_position(value, low, high).to_string(),
            )
          None => ()
        }
      }
      if coordinates.length() > 1 {
        body += "<polyline fill=\"none\" stroke=\"" +
          series_color(series_index) +
          "\" stroke-width=\"2.5\" stroke-linejoin=\"round\" stroke-linecap=\"round\" points=\"" +
          coordinates.join(" ") +
          "\"/>"
      }
    }
  }
  for point in plot.points {
    let x_index = string_index(x_values, point.x)
    let point_series = if point.series == "" { "value" } else { point.series }
    let series_index = string_index(series_values, point_series).max(0)
    let x = x_position(x_index.max(0), x_values.length())
    let y = y_position(point.y, low, high)
    body += "<circle cx=\"" +
      x.to_string() +
      "\" cy=\"" +
      y.to_string() +
      "\" r=\"4\" fill=\"" +
      series_color(series_index) +
      "\" fill-opacity=\"0.82\"><title>" +
      escape_xml(point_series + " — " + point.x + ": " + point.y.to_string()) +
      " " +
      escape_xml(plot.unit) +
      "</title></circle>"
  }
  body
}

///|
fn svg_heatmap(
  plot : @ir.Plot,
  x_values : Array[String],
  series_values : Array[String],
  low : Double,
  high : Double,
) -> String {
  let mut body = ""
  let cell_width = 804.0 / x_values.length().max(1).to_double()
  let cell_height = 252.0 / series_values.length().max(1).to_double()
  for series_index = 0
      series_index < series_values.length()
      series_index = series_index + 1 {
    for x_index = 0; x_index < x_values.length(); x_index = x_index + 1 {
      match average_at(plot, x_values[x_index], series_values[series_index]) {
        Some(value) => {
          let opacity = 0.18 + (value - low) / (high - low) * 0.72
          let x = 76.0 + x_index.to_double() * cell_width
          let y = 102.0 + series_index.to_double() * cell_height
          body += "<rect x=\"" +
            x.to_string() +
            "\" y=\"" +
            y.to_string() +
            "\" width=\"" +
            cell_width.to_string() +
            "\" height=\"" +
            cell_height.to_string() +
            "\" fill=\"" +
            series_color(series_index) +
            "\" fill-opacity=\"" +
            opacity.to_string() +
            "\" stroke=\"#ffffff\"><title>" +
            escape_xml(
              series_values[series_index] +
              " — " +
              x_values[x_index] +
              ": " +
              value.to_string() +
              " " +
              plot.unit,
            ) +
            "</title></rect>"
        }
        None => ()
      }
    }
  }
  body
}

///|
pub fn plot_json(document : @ir.PlotDocument) -> String {
  let plot_values = document.plots.map(plot => {
    let point_values = plot.points.map(point => {
      Json::object({
        "x": Json::string(point.x),
        "y": Json::number(point.y),
        "series": Json::string(point.series),
      })
    })
    Json::object({
      "kind": Json::string(kind_name(plot.kind)),
      "title": Json::string(plot.title),
      "unit": Json::string(plot.unit),
      "interval_kind": Json::string(plot.interval_kind),
      "points": Json::array(point_values),
    })
  })
  let mismatch_values = document.differential.mismatches.map(row => {
    Json::object({
      "implementation": Json::string(row.implementation),
      "operation": Json::string(row.operation),
      "operands": Json::array(row.operands.map(Json::string)),
      "expected": Json::string(row.expected),
      "actual": Json::string(row.actual),
      "flags_diff": Json::string(row.flags_diff),
      "trap": Json::string(row.trap),
      "fingerprint": Json::string(row.fingerprint),
      "replay_command": Json::string(row.replay_command),
    })
  })
  let capability_values = document.differential.capabilities.map(cell => {
    Json::object({
      "implementation": Json::string(cell.implementation),
      "outcome_kind": Json::string(cell.outcome_kind),
      "count": Json::number(cell.count.to_double()),
    })
  })
  let counterexample_values = document.differential.counterexamples.map(value => {
    Json::object({
      "implementation": Json::string(value.implementation),
      "minimal_input": Json::string(value.minimal_input),
      "fingerprint": Json::string(value.fingerprint),
      "shrink_path": Json::array(value.shrink_path.map(Json::string)),
      "replay_command": Json::string(value.replay_command),
    })
  })
  let corpus = document.differential.corpus
  Json::object({
    "schema_version": Json::string(document.schema_version.identifier()),
    "run_id": Json::string(document.run_id),
    "target": Json::string(document.target),
    "plots": Json::array(plot_values),
    "differential": Json::object({
      "mismatches": Json::array(mismatch_values),
      "capabilities": Json::array(capability_values),
      "counterexamples": Json::array(counterexample_values),
      "corpus": Json::object({
        "total": Json::number(corpus.total.to_double()),
        "passed": Json::number(corpus.passed.to_double()),
        "failed": Json::number(corpus.failed.to_double()),
        "unsupported": Json::number(corpus.unsupported.to_double()),
        "expected_difference": Json::number(
          corpus.expected_difference.to_double(),
        ),
      }),
    }),
  }).stringify()
}

///|
fn json_string(object : Map[String, Json], key : String) -> String {
  match object.get(key) {
    Some(String(value)) => value
    _ => ""
  }
}

///|
fn json_int(object : Map[String, Json], key : String) -> Int {
  match object.get(key) {
    Some(Number(value, ..)) => value.to_int()
    _ => 0
  }
}

///|
fn json_strings(object : Map[String, Json], key : String) -> Array[String] {
  match object.get(key) {
    Some(Array(values)) =>
      values.filter_map(value => {
        match value {
          String(text) => Some(text)
          _ => None
        }
      })
    _ => []
  }
}

///|
fn add_capability(
  cells : Array[@ir.CapabilityCell],
  implementation : String,
  outcome_kind : String,
) -> Unit {
  for index = 0; index < cells.length(); index = index + 1 {
    if cells[index].implementation == implementation &&
      cells[index].outcome_kind == outcome_kind {
      cells[index] = @ir.CapabilityCell::new(
        implementation,
        outcome_kind,
        cells[index].count + 1,
      )
      return
    }
  }
  cells.push(@ir.CapabilityCell::new(implementation, outcome_kind, 1))
}

///|
priv struct ReportObservation {
  case_id : String
  implementation : String
  dataset_id : Int
  elapsed_us : Double
}

///|
priv struct FailedBenchmarkKey {
  case_id : String
  implementation : String
  dataset_id : Int
}

///|
fn observation_failed(
  observation : ReportObservation,
  failures : Array[FailedBenchmarkKey],
) -> Bool {
  failures.any(failure => {
    failure.case_id == observation.case_id &&
    failure.implementation == observation.implementation &&
    failure.dataset_id == observation.dataset_id
  })
}

///|
pub fn document_from_jsonl(
  source : String,
  target? : String = "unknown",
) -> Result[@ir.PlotDocument, String] {
  let observations : Array[ReportObservation] = []
  let failed_benchmarks : Array[FailedBenchmarkKey] = []
  let mismatches = []
  let capabilities = []
  let counterexamples = []
  let mut run_id = "unidentified"
  let mut passed = 0
  let mut failed = 0
  let mut unsupported = 0
  let mut expected_difference = 0
  let mut line_number = 0
  for line_view in source.split("\n") {
    line_number += 1
    let line = line_view.to_owned()
    if line.trim().length() == 0 {
      continue
    }
    let value = try @json.parse(line) catch {
      _ => return Err("invalid JSONL at line " + line_number.to_string())
    } noraise {
      value => value
    }
    guard value is Object(object) else {
      return Err("expected JSON object at line " + line_number.to_string())
    }
    match object.get("artifact_version") {
      Some(String(version)) if version !=
        @model.ArtifactVersion::V1.identifier() =>
        return Err(
          "unsupported artifact version '" +
          version +
          "' at line " +
          line_number.to_string(),
        )
      Some(String(_)) | None => ()
      Some(_) =>
        return Err(
          "invalid artifact version at line " + line_number.to_string(),
        )
    }
    match object.get("type") {
      Some(String("observation")) => {
        guard object.get("implementation") is Some(String(implementation)) else {
          return Err(
            "missing implementation at line " + line_number.to_string(),
          )
        }
        guard object.get("dataset_id") is Some(Number(dataset_id, ..)) else {
          return Err("missing dataset_id at line " + line_number.to_string())
        }
        guard object.get("elapsed_us") is Some(Number(elapsed_us, ..)) else {
          return Err("missing elapsed_us at line " + line_number.to_string())
        }
        let valid = match object.get("valid") {
          Some(True) => true
          Some(False) => false
          _ => true
        }
        let kept = match object.get("batch_sink") {
          Some(String(value)) => value == "kept"
          _ => true
        }
        if valid && kept {
          observations.push({
            case_id: json_string(object, "case"),
            implementation,
            dataset_id: dataset_id.to_int(),
            elapsed_us,
          })
        }
      }
      Some(String("validation")) => {
        let implementation = json_string(object, "implementation")
        let actual_kind = json_string(object, "actual_kind")
        add_capability(
          capabilities,
          implementation,
          if actual_kind == "" {
            "unclassified"
          } else {
            actual_kind
          },
        )
        let status = json_string(object, "status")
        if status == "invalid" || status == "infrastructure_failure" {
          let case_id = json_string(object, "case")
          match object.get("dataset_id") {
            Some(Number(dataset_id, ..)) if !case_id.is_empty() =>
              failed_benchmarks.push({
                case_id,
                implementation,
                dataset_id: dataset_id.to_int(),
              })
            _ => ()
          }
          let expected_flags = json_strings(object, "expected_flags")
          let actual_flags = json_strings(object, "actual_flags")
          mismatches.push(
            @ir.MismatchRow::new(
              implementation,
              json_string(object, "operation"),
              json_strings(object, "operands"),
              json_string(object, "expected"),
              json_string(object, "actual"),
              expected_flags.join(", ") + " → " + actual_flags.join(", "),
              json_string(object, "trap"),
              json_string(object, "fingerprint"),
              json_string(object, "replay_command"),
            ),
          )
        }
      }
      Some(String("validation_failure")) =>
        counterexamples.push(
          @ir.Counterexample::new(
            json_string(object, "implementation"),
            json_string(object, "minimal_input"),
            json_string(object, "minimal_fingerprint"),
            json_strings(object, "shrink_path"),
            json_string(object, "replay_command"),
          ),
        )
      Some(String("summary")) => {
        if object.get("run_id") is Some(String(value)) {
          run_id = value
        }
        passed = json_int(object, "passed_count")
        failed = json_int(object, "failed_count")
        unsupported = json_int(object, "unsupported_count")
        expected_difference = json_int(object, "expected_difference_count")
      }
      _ => ()
    }
  }
  let points = observations.filter_map(observation => {
    if observation_failed(observation, failed_benchmarks) {
      None
    } else {
      Some(
        @ir.PlotPoint::new(
          observation.dataset_id.to_string(),
          observation.elapsed_us,
          observation.implementation,
        ),
      )
    }
  })
  if points.is_empty() && mismatches.is_empty() && counterexamples.is_empty() {
    Err("JSONL contains no observation or differential events")
  } else {
    let plots = if points.is_empty() {
      []
    } else {
      [
        @ir.Plot::new(
          @ir.PlotKind::Scaling,
          "Benchmark observations",
          "µs/op",
          "raw",
          points,
        ),
      ]
    }
    let total = passed + failed + unsupported + expected_difference
    Ok(
      @ir.PlotDocument::new(
        run_id,
        target,
        plots,
        differential=@ir.DifferentialReport::new(
          mismatches,
          capabilities,
          counterexamples,
          @ir.CorpusSummary::new(
            total, passed, failed, unsupported, expected_difference,
          ),
        ),
      ),
    )
  }
}

///|
pub fn plot_svg(plot : @ir.Plot) -> String {
  let x_values = unique_x_values(plot)
  let series_values = unique_series(plot)
  let (low, high) = y_bounds(plot)
  let mut body = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 960 420\" role=\"img\" aria-labelledby=\"plot-title plot-description\">"
  body += "<title id=\"plot-title\">" + escape_xml(plot.title) + "</title>"
  body += "<desc id=\"plot-description\">" +
    escape_xml(kind_name(plot.kind) + " plot, " + plot.interval_kind) +
    "</desc>"
  body += "<style>.grid{stroke:#e2e8f0;stroke-width:1}.axis{stroke:#64748b;stroke-width:1.2}.tick{fill:#64748b;font:12px ui-sans-serif,system-ui,sans-serif}.axis-label{fill:#475569;font:600 12px ui-sans-serif,system-ui,sans-serif}.legend{fill:#334155;font:12px ui-sans-serif,system-ui,sans-serif}</style>"
  body += svg_axes(plot, x_values, low, high)
  body += svg_legend(series_values)
  body += if plot.kind is @ir.PlotKind::Heatmap {
    svg_heatmap(plot, x_values, series_values, low, high)
  } else {
    svg_series_plot(plot, x_values, series_values, low, high)
  }
  if plot.points.is_empty() {
    body += "<text class=\"axis-label\" x=\"478\" y=\"228\" text-anchor=\"middle\">No observations</text>"
  }
  body + "</svg>"
}

///|
fn differential_html(report : @ir.DifferentialReport) -> String {
  let corpus = report.corpus
  let summary = "<section class=\"panel\"><h2>Corpus outcomes</h2><p class=\"denominator\">Total " +
    corpus.total.to_string() +
    " · passed " +
    corpus.passed.to_string() +
    " · failed " +
    corpus.failed.to_string() +
    " · unsupported " +
    corpus.unsupported.to_string() +
    " · expected differences " +
    corpus.expected_difference.to_string() +
    "</p></section>"
  let mismatch_rows = report.mismatches
    .map(row => {
      "<tr><td>" +
      escape_xml(row.implementation) +
      "</td><td>" +
      escape_xml(row.operation) +
      "</td><td><code>" +
      escape_xml(row.operands.join(", ")) +
      "</code></td><td><code>" +
      escape_xml(row.expected) +
      "</code></td><td><code>" +
      escape_xml(row.actual) +
      "</code></td><td>" +
      escape_xml(row.flags_diff) +
      "</td><td>" +
      escape_xml(row.trap) +
      "</td><td><code>" +
      escape_xml(row.fingerprint) +
      "</code></td><td><code>" +
      escape_xml(row.replay_command) +
      "</code></td></tr>"
    })
    .join("\n")
  let mismatches = "<section class=\"panel\"><h2>Mismatches</h2><div class=\"table-wrap\"><table><thead><tr><th>Implementation</th><th>Operation</th><th>Operands</th><th>Expected</th><th>Actual</th><th>Flags diff</th><th>Trap</th><th>Fingerprint</th><th>Replay</th></tr></thead><tbody>" +
    mismatch_rows +
    "</tbody></table></div></section>"
  let capability_rows = report.capabilities
    .map(cell => {
      "<tr><td>" +
      escape_xml(cell.implementation) +
      "</td><td>" +
      escape_xml(cell.outcome_kind) +
      "</td><td>" +
      cell.count.to_string() +
      "</td></tr>"
    })
    .join("\n")
  let capabilities = "<section class=\"panel\"><h2>Capability coverage matrix</h2><div class=\"table-wrap\"><table><thead><tr><th>Implementation</th><th>Outcome</th><th>Cases</th></tr></thead><tbody>" +
    capability_rows +
    "</tbody></table></div></section>"
  let counterexample_rows = report.counterexamples
    .map(counterexample => {
      "<tr><td>" +
      escape_xml(counterexample.implementation) +
      "</td><td><code>" +
      escape_xml(counterexample.minimal_input) +
      "</code></td><td><code>" +
      escape_xml(counterexample.fingerprint) +
      "</code></td><td>" +
      counterexample.shrink_path.length().to_string() +
      "</td><td><code>" +
      escape_xml(counterexample.replay_command) +
      "</code></td></tr>"
    })
    .join("\n")
  let counterexamples = "<section class=\"panel\"><h2>Minimal counterexamples</h2><div class=\"table-wrap\"><table><thead><tr><th>Implementation</th><th>Minimal input</th><th>Fingerprint</th><th>Shrink steps</th><th>Replay</th></tr></thead><tbody>" +
    counterexample_rows +
    "</tbody></table></div></section>"
  summary + mismatches + capabilities + counterexamples
}

///|
pub fn html(document : @ir.PlotDocument) -> String {
  let figures = document.plots
    .map(plot => {
      "<figure><figcaption><span>" +
      escape_xml(plot.title) +
      "</span><small>" +
      escape_xml(kind_name(plot.kind) + " · " + plot.interval_kind) +
      "</small></figcaption>" +
      plot_svg(plot) +
      "</figure>"
    })
    .join("\n")
  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>mare_mark · " +
  escape_xml(document.run_id) +
  "</title><style>:root{color-scheme:light;background:#f1f5f9;color:#0f172a;font-family:Inter,ui-sans-serif,system-ui,sans-serif}*{box-sizing:border-box}body{margin:0}.shell{width:min(1200px,calc(100% - 32px));margin:0 auto;padding:48px 0 72px}header{margin-bottom:28px}h1{font-size:clamp(2rem,5vw,3.5rem);letter-spacing:-.04em;margin:0 0 10px}h2{margin:0 0 14px;font-size:1.2rem}.meta{display:flex;gap:10px;flex-wrap:wrap}.tag{background:#dbeafe;color:#1e3a8a;border-radius:999px;padding:6px 11px;font-size:.8rem;font-weight:700}.panel,figure{margin:0 0 24px;background:#fff;border:1px solid #dbe3ee;border-radius:18px;padding:18px;box-shadow:0 14px 35px rgba(15,23,42,.07)}figcaption{display:flex;justify-content:space-between;gap:16px;align-items:baseline;font-weight:750;padding:2px 8px 12px}figcaption small{color:#64748b;font-weight:600}svg{display:block;width:100%;height:auto}.denominator{margin:0;color:#334155}.table-wrap{overflow:auto}table{border-collapse:collapse;width:100%;font-size:.84rem}th,td{text-align:left;vertical-align:top;padding:9px;border-bottom:1px solid #e2e8f0}th{color:#475569;font-size:.75rem;text-transform:uppercase;letter-spacing:.04em}code{font-size:.78rem;overflow-wrap:anywhere}@media(max-width:640px){.shell{width:min(100% - 16px,1200px);padding-top:24px}.panel,figure{padding:8px;border-radius:12px}figcaption{align-items:flex-start;flex-direction:column}}</style></head><body><main class=\"shell\"><header><h1>mare_mark report</h1><div class=\"meta\"><span class=\"tag\">Run " +
  escape_xml(document.run_id) +
  "</span><span class=\"tag\">Target " +
  escape_xml(document.target) +
  "</span><span class=\"tag\">Schema " +
  escape_xml(document.schema_version.identifier()) +
  "</span></div></header>" +
  differential_html(document.differential) +
  figures +
  "</main></body></html>"
}
