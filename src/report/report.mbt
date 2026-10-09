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
/// The x values of `plot` in axis order, their horizontal positions, and
/// whether each one gets a tick label. A `Linear` axis sorts the values
/// numerically and places them by value; it falls back to `Categorical` when
/// a value is not a finite number, and heatmaps are always categorical.
fn x_layout(plot : @ir.Plot) -> (Array[String], Array[Double], Array[Bool]) {
  let values = unique_x_values(plot)
  let numbers = values.map(finite_number)
  let linear = (
      plot.x_axis is @ir.AxisScale::Linear || plot.x_axis is @ir.AxisScale::Log
    ) &&
    !(plot.kind is @ir.PlotKind::Heatmap) &&
    !values.is_empty() &&
    numbers.all(number => number is Some(_))
  if !linear {
    let count = values.length()
    let stride = ((count + 9) / 10).max(1)
    let positions = Array::makei(count, index => x_position(index, count))
    let labelled = Array::makei(count, index => {
      index % stride == 0 || index == count - 1
    })
    return (values, positions, labelled)
  }
  let order = Array::makei(values.length(), index => {
    (numbers[index].unwrap_or(0.0), index)
  })
  order.sort()
  let log_axis = uses_log_x(plot)
  let low = if log_axis { @math.log10(order[0].0) } else { order[0].0 }
  let high = if log_axis {
    @math.log10(order[order.length() - 1].0)
  } else {
    order[order.length() - 1].0
  }
  let positions = order.map(entry => {
    let value = if log_axis { @math.log10(entry.0) } else { entry.0 }
    if high == low {
      478.0
    } else {
      76.0 + (value - low) * 804.0 / (high - low)
    }
  })
  let labelled = []
  let mut last_label = -1.0e9
  for position in positions {
    let visible = position - last_label >= 56.0
    if visible {
      last_label = position
    }
    labelled.push(visible)
  }
  (order.map(entry => values[entry.1]), positions, labelled)
}

///|
fn y_position(value : Double, low : Double, high : Double) -> Double {
  354.0 - (value - low) * 252.0 / (high - low)
}

///|
fn is_positive_finite(value : Double) -> Bool {
  value > 0.0 && !value.is_nan() && !value.is_inf()
}

///|
fn has_log_span(values : Array[Double]) -> Bool {
  if values.is_empty() || !values.all(is_positive_finite) {
    return false
  }
  let mut low = values[0]
  let mut high = values[0]
  for value in values {
    low = low.min(value)
    high = high.max(value)
  }
  low < high && high / low >= 100.0
}

///|
fn uses_log_x(plot : @ir.Plot) -> Bool {
  !(plot.kind is @ir.PlotKind::Heatmap) &&
  plot.x_axis is @ir.AxisScale::Log &&
  !unique_x_values(plot).is_empty() &&
  unique_x_values(plot).all(value => {
    match finite_number(value) {
      Some(number) => is_positive_finite(number)
      None => false
    }
  })
}

///|
fn uses_log_y(plot : @ir.Plot) -> Bool {
  plot.y_axis is @ir.AxisScale::Log &&
  !plot.points.is_empty() &&
  plot.points.all(point => is_positive_finite(point.y))
}

///|
fn y_transform(plot : @ir.Plot, value : Double) -> Double {
  if uses_log_y(plot) {
    @math.log10(value)
  } else {
    value
  }
}

///|
/// `multiplier × 10^exponent`, correctly rounded, or `0.0` when it is not
/// representable.
fn decimal_value(multiplier : Int, exponent : Int) -> Double {
  let text = multiplier.to_string() + "e" + exponent.to_string()
  let value = try @string.parse_double(text) catch {
    _ => return 0.0
  } noraise {
    value => value
  }
  value
}

///|
/// Labelled ticks of a base-10 axis covering the data range `[low, high]`,
/// where one decade spans `pixels_per_decade` pixels and labels must stay at
/// least `spacing` pixels apart.
///
/// Every power of ten in range is labelled. When decades are closer than
/// `spacing`, every k-th decade is labelled instead (exponents divisible by
/// the smallest k that keeps them apart), so the labels stay uniform. The 2×
/// and 5× ticks are added only when a decade is wide enough to keep all of
/// them `spacing` apart. A range that holds no 1-2-5 value labels its
/// endpoints, and a degenerate range labels its single value.
fn log_axis_ticks(
  low : Double,
  high : Double,
  pixels_per_decade : Double,
  spacing : Double,
) -> Array[Double] {
  if !is_positive_finite(low) || !is_positive_finite(high) || high < low {
    return []
  }
  let low_log = @math.log10(low)
  let high_log = @math.log10(high)
  if high_log == low_log {
    return [low]
  }
  let stride = if pixels_per_decade >= spacing {
    1
  } else {
    @math.ceil(spacing / pixels_per_decade).to_int().max(1)
  }
  let minor = stride == 1 && pixels_per_decade * @math.log10(2.0) >= spacing
  let multipliers = if minor { [1, 2, 5] } else { [1] }
  let ticks = []
  for exponent = @math.floor(low_log).to_int()
      exponent <= @math.ceil(high_log).to_int()
      exponent = exponent + 1 {
    if exponent % stride != 0 {
      continue
    }
    for multiplier in multipliers {
      let value = decimal_value(multiplier, exponent)
      if is_positive_finite(value) && value >= low && value <= high {
        ticks.push(value)
      }
    }
  }
  if !ticks.is_empty() {
    ticks
  } else if (high_log - low_log) * pixels_per_decade >= spacing {
    [low, high]
  } else {
    [low]
  }
}

///|
fn numeric_bounds(values : Array[Double]) -> (Double, Double) {
  let mut low = values[0]
  let mut high = values[0]
  for value in values {
    low = low.min(value)
    high = high.max(value)
  }
  (low, high)
}

///|
fn y_axis_bounds(plot : @ir.Plot) -> (Double, Double) {
  if plot.points.is_empty() {
    (0.0, 1.0)
  } else if uses_log_y(plot) {
    let mut min_value = plot.points[0].y
    let mut max_value = plot.points[0].y
    for point in plot.points {
      min_value = min_value.min(point.y)
      max_value = max_value.max(point.y)
    }
    let log_low = @math.log10(min_value)
    let log_high = @math.log10(max_value)
    if min_value == max_value {
      (log_low - 0.1, log_high + 0.1)
    } else {
      let padding = (log_high - log_low) * 0.08
      (log_low - padding, log_high + padding)
    }
  } else {
    y_bounds(plot)
  }
}

///|
/// Rounds `value` to three decimals for display. Magnitudes below 0.001 or
/// from 1e15 up, where that rounding would erase or overflow the value, keep
/// their shortest round-trip form.
fn format_number(value : Double) -> String {
  let magnitude = value.abs()
  if value.is_nan() ||
    value.is_inf() ||
    magnitude >= 1.0e15 ||
    (magnitude > 0.0 && magnitude < 0.001) {
    value.to_string()
  } else {
    ((value * 1000.0).round() / 1000.0).to_string()
  }
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
  x_positions : Array[Double],
  x_labelled : Array[Bool],
  low : Double,
  high : Double,
) -> String {
  let mut body = ""
  if uses_log_y(plot) {
    let values = plot.points.map(point => point.y)
    let (minimum, maximum) = numeric_bounds(values)
    // Only labelled ticks get grid lines, so the count stays bounded by the
    // label spacing however many decades the data spans.
    for value in log_axis_ticks(minimum, maximum, 252.0 / (high - low), 28.0) {
      let y = y_position(@math.log10(value), low, high)
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
  } else {
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
  }
  body += "<line class=\"axis\" x1=\"76\" y1=\"102\" x2=\"76\" y2=\"354\"/>"
  body += "<line class=\"axis\" x1=\"76\" y1=\"354\" x2=\"880\" y2=\"354\"/>"
  if uses_log_x(plot) {
    let values = x_values.map(value => finite_number(value).unwrap())
    let (minimum, maximum) = numeric_bounds(values)
    let low_log = @math.log10(minimum)
    let high_log = @math.log10(maximum)
    let span = high_log - low_log
    let pixels_per_decade = if span > 0.0 { 804.0 / span } else { 804.0 }
    for value in log_axis_ticks(minimum, maximum, pixels_per_decade, 56.0) {
      let x = if span > 0.0 {
        76.0 + (@math.log10(value) - low_log) * pixels_per_decade
      } else {
        478.0
      }
      body += "<line class=\"axis\" x1=\"" +
        x.to_string() +
        "\" y1=\"354\" x2=\"" +
        x.to_string() +
        "\" y2=\"360\"/><text class=\"tick\" x=\"" +
        x.to_string() +
        "\" y=\"378\" text-anchor=\"middle\">" +
        escape_xml(format_number(value)) +
        "</text>"
    }
  } else {
    for index = 0; index < x_values.length(); index = index + 1 {
      if x_labelled[index] {
        let x = x_positions[index]
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
  }
  body += "<text class=\"axis-label\" x=\"22\" y=\"228\" text-anchor=\"middle\" transform=\"rotate(-90 22 228)\">" +
    escape_xml(plot.unit + (if uses_log_y(plot) { " (log₁₀)" } else { "" })) +
    "</text>"
  if !plot.x_label.is_empty() {
    body += "<text class=\"axis-label\" x=\"478\" y=\"408\" text-anchor=\"middle\">" +
      escape_xml(
        plot.x_label + (if uses_log_x(plot) { " (log₁₀)" } else { "" }),
      ) +
      "</text>"
  }
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
  x_positions : Array[Double],
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
              x_positions[x_index].to_string() +
              "," +
              y_position(y_transform(plot, value), low, high).to_string(),
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
    let x = x_positions[x_index.max(0)]
    let y = y_position(y_transform(plot, point.y), low, high)
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
fn axis_scale_name(scale : @ir.AxisScale) -> String {
  match scale {
    @ir.AxisScale::Categorical => "categorical"
    @ir.AxisScale::Linear => "linear"
    @ir.AxisScale::Log => "log"
  }
}

///|
/// JSON number for a `Double`; non-finite values are the strings `"NaN"`,
/// `"Infinity"` and `"-Infinity"`, as in the JSONL protocol.
fn number_json(value : Double) -> Json {
  if value.is_nan() {
    Json::string("NaN")
  } else if value.is_pos_inf() {
    Json::string("Infinity")
  } else if value.is_neg_inf() {
    Json::string("-Infinity")
  } else {
    Json::number(value)
  }
}

///|
fn comparison_row_json(row : @ir.ComparisonRow) -> Json {
  Json::object({
    "case": Json::string(row.case_id),
    "scale": Json::string(row.scale),
    "baseline": Json::string(row.baseline),
    "candidate": Json::string(row.candidate),
    "decision": Json::string(row.decision.text()),
    "reason": Json::string(row.reason),
    "estimate": match row.estimate {
      Some(estimate) =>
        Json::object({
          "baseline_median_us": number_json(estimate.baseline_median_us),
          "candidate_median_us": number_json(estimate.candidate_median_us),
          "median_delta_us": number_json(estimate.median_delta_us),
          "relative_delta_pct": number_json(estimate.relative_delta_pct),
          "speedup": number_json(estimate.speedup),
        })
      None => Json::null()
    },
    "interval": match row.interval {
      Some(interval) =>
        Json::object({
          "low_us": number_json(interval.low_us),
          "high_us": number_json(interval.high_us),
          "low_pct": number_json(interval.low_pct),
          "high_pct": number_json(interval.high_pct),
        })
      None => Json::null()
    },
    "blocks_used": Json::number(row.blocks_used.to_double()),
    "blocks_incomplete": Json::number(row.blocks_incomplete.to_double()),
    "blocks_outliers": Json::number(row.blocks_outliers.to_double()),
    "seed": Json::string(row.seed.to_string()),
  })
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
      "x_axis": Json::string(axis_scale_name(plot.x_axis)),
      "y_axis": Json::string(axis_scale_name(plot.y_axis)),
      "x_label": Json::string(plot.x_label),
      "note": Json::string(plot.note),
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
  let comparisons = document.comparisons
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
    "comparisons": Json::object({
      "practical_delta_pct": number_json(comparisons.practical_delta_pct),
      "outlier_policy": Json::string(comparisons.outlier_policy),
      "confidence_pct": number_json(comparisons.confidence_pct),
      "resamples": Json::number(comparisons.resamples.to_double()),
      "min_blocks": Json::number(comparisons.min_blocks.to_double()),
      "run_seed": Json::string(comparisons.run_seed.to_string()),
      "protocol_source": Json::string(
        if comparisons.protocol_recorded {
          "record"
        } else {
          "default"
        },
      ),
      "seed_source": Json::string(
        if comparisons.seed_recorded {
          "record"
        } else {
          "default"
        },
      ),
      "note": Json::string(comparisons.note),
      "rows": Json::array(comparisons.rows.map(comparison_row_json)),
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
/// An observation line that passed the `valid` and `batch_sink` filters.
priv struct ReportObservation {
  case_id : String
  implementation : String
  dataset_id : Int
  /// The `phase` field, or `""` for records written before it existed.
  phase : String
  /// The `scale` field, or `None` for records written before it existed.
  scale : String?
  /// The `block_id` field, or `None` for records written without it.
  block_id : Int?
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
/// Where the x value of a timing group comes from.
priv enum ScaleSource {
  /// The observation's `scale` field.
  Recorded
  /// The observation has no `scale` field; `dataset_id` stands in for it.
  DatasetId
} derive(Eq)

///|
/// The confirmatory samples of one implementation at one scale of one case.
/// Several datasets may share a scale; their samples are pooled here.
priv struct TimingGroup {
  scale : String
  scale_source : ScaleSource
  implementation : String
  /// Confirmatory per-iteration times (`elapsed_us`), in input order.
  elapsed_us : Array[Double]
  /// The block of each entry of `elapsed_us`, `None` where it is not recorded.
  block_ids : Array[Int?]
}

///|
priv struct CaseTimings {
  case_id : String
  /// Implementations of every phase, in order of first appearance.
  implementations : Array[String]
  /// Groups in order of first appearance of (scale, implementation).
  groups : Array[TimingGroup]
  /// Observations left out because their phase is not confirmatory, by phase,
  /// in order of first appearance.
  excluded_by_phase : Map[String, Int]
}

///|
/// A record without `phase` predates the field and is treated as
/// confirmatory; every other phase (`exploratory`, or one this reader does
/// not know) is excluded from the timing statistics.
fn is_confirmatory(phase : String) -> Bool {
  phase == "" || phase == @model.ObservationPhase::Confirmatory.text()
}

///|
/// Groups the confirmatory observations by (case, scale, implementation),
/// dropping observations of failed benchmark keys. Cases, scales and
/// implementations keep their order of first appearance in `observations`.
/// A case whose observations are all excluded still appears, with no groups,
/// so that its exclusions can be reported.
fn confirmatory_timings(
  observations : Array[ReportObservation],
  failures : Array[FailedBenchmarkKey],
) -> Array[CaseTimings] {
  let cases : Array[CaseTimings] = []
  for observation in observations {
    if observation_failed(observation, failures) {
      continue
    }
    let case_timings = match
      cases.search_by(item => item.case_id == observation.case_id) {
      Some(index) => cases[index]
      None => {
        let created = {
          case_id: observation.case_id,
          implementations: [],
          groups: [],
          excluded_by_phase: {},
        }
        cases.push(created)
        created
      }
    }
    if !case_timings.implementations.contains(observation.implementation) {
      case_timings.implementations.push(observation.implementation)
    }
    if !is_confirmatory(observation.phase) {
      let excluded = case_timings.excluded_by_phase
      let count = excluded.get_or_default(observation.phase, 0)
      excluded[observation.phase] = count + 1
      continue
    }
    let (scale, scale_source) = match observation.scale {
      Some(text) => (text, Recorded)
      None => (observation.dataset_id.to_string(), DatasetId)
    }
    match
      case_timings.groups.search_by(group => {
        group.scale == scale &&
        group.scale_source == scale_source &&
        group.implementation == observation.implementation
      }) {
      Some(index) => {
        let group = case_timings.groups[index]
        group.elapsed_us.push(observation.elapsed_us)
        group.block_ids.push(observation.block_id)
      }
      None =>
        case_timings.groups.push({
          scale,
          scale_source,
          implementation: observation.implementation,
          elapsed_us: [observation.elapsed_us],
          block_ids: [observation.block_id],
        })
    }
  }
  cases
}

///|
fn finite_number(text : String) -> Double? {
  let value = try @string.parse_double(text) catch {
    _ => return None
  } noraise {
    value => value
  }
  if value.is_nan() || value.is_inf() {
    None
  } else {
    Some(value)
  }
}

///|
fn excluded_note(excluded_by_phase : Map[String, Int]) -> String {
  if excluded_by_phase.is_empty() {
    return ""
  }
  let parts = []
  for phase, count in excluded_by_phase {
    parts.push(
      count.to_string() +
      " " +
      phase +
      (if count == 1 { " observation" } else { " observations" }),
    )
  }
  " Excluded: " + parts.join(", ") + "."
}

///|
/// The scaling plot of one case: one point per (implementation, scale), at the
/// median per-iteration time of the group's confirmatory samples.
fn scaling_plot(timings : CaseTimings) -> @ir.Plot {
  let groups = timings.groups
  let recorded = groups.any(group => group.scale_source == Recorded)
  let fallback = groups.any(group => group.scale_source == DatasetId)
  let x_label = if !fallback {
    "scale"
  } else if recorded {
    "scale (dataset_id where scale is not recorded)"
  } else {
    "dataset_id (scale not recorded)"
  }
  let points = groups.map(group => {
    let x = if recorded && group.scale_source == DatasetId {
      "dataset_id " + group.scale
    } else {
      group.scale
    }
    @ir.PlotPoint::new(
      x,
      @stats.summarize(group.elapsed_us).median,
      group.implementation,
    )
  })
  let x_numbers = points.map(point => finite_number(point.x))
  let x_axis = if !points.is_empty() &&
    x_numbers.all(number => number is Some(_)) {
    let numeric_values = x_numbers.map(number => number.unwrap())
    if has_log_span(numeric_values) {
      @ir.AxisScale::Log
    } else {
      @ir.AxisScale::Linear
    }
  } else {
    @ir.AxisScale::Categorical
  }
  let y_axis = if has_log_span(points.map(point => point.y)) {
    @ir.AxisScale::Log
  } else {
    @ir.AxisScale::Linear
  }
  let note = "Each point is the median per-iteration time (µs/op) of the confirmatory observations of one implementation at one " +
    (if recorded {
      "scale, pooled over every dataset and repetition at that scale."
    } else {
      "dataset_id, pooled over its repetitions."
    }) +
    excluded_note(timings.excluded_by_phase) +
    (if x_axis is @ir.AxisScale::Log {
      " X uses a base-10 logarithmic axis."
    } else {
      ""
    }) +
    (if y_axis is @ir.AxisScale::Log {
      " Y uses a base-10 logarithmic axis."
    } else {
      ""
    })
  @ir.Plot::new(
    @ir.PlotKind::Scaling,
    if timings.case_id.is_empty() {
      "Benchmark observations"
    } else {
      "Benchmark observations: " + timings.case_id
    },
    "µs/op",
    "median",
    points,
    x_axis~,
    y_axis~,
    x_label~,
    note~,
  )
}

///|

///|
/// Reads a JSONL record into a plot document: one scaling plot per case, the
/// differential tables, and the paired comparison of every implementation
/// against `baseline` at every scale of every case (see `ComparisonReport`).
///
/// `baseline` defaults to the first implementation that appears in each case;
/// an id that names no observed implementation is an error.
pub fn document_from_jsonl(
  source : String,
  target? : String = "unknown",
  baseline? : String,
) -> Result[@ir.PlotDocument, String] {
  let observations : Array[ReportObservation] = []
  let implementations_seen : Array[String] = []
  let mut protocol : @model.RunProtocol? = None
  let mut run_seed : UInt64? = None
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
        let phase = match object.get("phase") {
          Some(String(value)) => value
          None => ""
          Some(_) =>
            return Err("invalid phase at line " + line_number.to_string())
        }
        let scale = match object.get("scale") {
          Some(String(value)) => Some(value)
          None => None
          Some(_) =>
            return Err("invalid scale at line " + line_number.to_string())
        }
        let block_id = match object.get("block_id") {
          Some(Number(value, ..)) => Some(value.to_int())
          None => None
          Some(_) =>
            return Err("invalid block_id at line " + line_number.to_string())
        }
        if !implementations_seen.contains(implementation) {
          implementations_seen.push(implementation)
        }
        if valid && kept {
          observations.push({
            case_id: json_string(object, "case"),
            implementation,
            dataset_id: dataset_id.to_int(),
            phase,
            scale,
            block_id,
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
        match object.get("protocol") {
          Some(json) =>
            match @event.protocol_from_json(json) {
              Ok(value) => protocol = Some(value)
              Err(message) =>
                return Err(
                  "invalid protocol at line " +
                  line_number.to_string() +
                  ": " +
                  message,
                )
            }
          None => ()
        }
        match object.get("seed") {
          Some(String(text)) =>
            match decimal_uint64(text) {
              Some(value) => run_seed = Some(value)
              None =>
                return Err("invalid seed at line " + line_number.to_string())
            }
          None => ()
          Some(_) =>
            return Err("invalid seed at line " + line_number.to_string())
        }
      }
      _ => ()
    }
  }
  match baseline {
    Some(id) if !implementations_seen.contains(id) =>
      return Err(
        "unknown baseline '" +
        id +
        "'; implementations in the record: " +
        (if implementations_seen.is_empty() {
          "none"
        } else {
          implementations_seen.join(", ")
        }),
      )
    _ => ()
  }
  let timings = confirmatory_timings(observations, failed_benchmarks)
  let plots = timings.map(scaling_plot)
  let comparisons = comparison_report(
    timings,
    baseline,
    comparison_settings(protocol, run_seed),
  )
  if plots.is_empty() && mismatches.is_empty() && counterexamples.is_empty() {
    Err("JSONL contains no observation or differential events")
  } else {
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
        comparisons~,
      ),
    )
  }
}

///|
pub fn plot_svg(plot : @ir.Plot) -> String {
  let (x_values, x_positions, x_labelled) = x_layout(plot)
  let series_values = unique_series(plot)
  let (low, high) = y_axis_bounds(plot)
  let mut body = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 960 420\" role=\"img\" aria-labelledby=\"plot-title plot-description\">"
  body += "<title id=\"plot-title\">" + escape_xml(plot.title) + "</title>"
  body += "<desc id=\"plot-description\">" +
    escape_xml(
      kind_name(plot.kind) +
      " plot, " +
      plot.interval_kind +
      (if plot.note.is_empty() { "" } else { ". " + plot.note }),
    ) +
    "</desc>"
  body += "<style>.grid{stroke:#e2e8f0;stroke-width:1}.axis{stroke:#64748b;stroke-width:1.2}.tick{fill:#64748b;font:12px ui-sans-serif,system-ui,sans-serif}.axis-label{fill:#475569;font:600 12px ui-sans-serif,system-ui,sans-serif}.legend{fill:#334155;font:12px ui-sans-serif,system-ui,sans-serif}</style>"
  body += svg_axes(plot, x_values, x_positions, x_labelled, low, high)
  body += svg_legend(series_values)
  body += if plot.kind is @ir.PlotKind::Heatmap {
    svg_heatmap(plot, x_values, series_values, low, high)
  } else {
    svg_series_plot(plot, x_values, x_positions, series_values, low, high)
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
      "</small>" +
      (if plot.note.is_empty() {
        ""
      } else {
        "<p class=\"note\">" + escape_xml(plot.note) + "</p>"
      }) +
      "</figcaption>" +
      plot_svg(plot) +
      "</figure>"
    })
    .join("\n")
  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>mare_mark · " +
  escape_xml(document.run_id) +
  "</title><style>:root{color-scheme:light;background:#f1f5f9;color:#0f172a;font-family:Inter,ui-sans-serif,system-ui,sans-serif}*{box-sizing:border-box}body{margin:0}.shell{width:min(1200px,calc(100% - 32px));margin:0 auto;padding:48px 0 72px}header{margin-bottom:28px}h1{font-size:clamp(2rem,5vw,3.5rem);letter-spacing:-.04em;margin:0 0 10px}h2{margin:0 0 14px;font-size:1.2rem}.meta{display:flex;gap:10px;flex-wrap:wrap}.tag{background:#dbeafe;color:#1e3a8a;border-radius:999px;padding:6px 11px;font-size:.8rem;font-weight:700}.panel,figure{margin:0 0 24px;background:#fff;border:1px solid #dbe3ee;border-radius:18px;padding:18px;box-shadow:0 14px 35px rgba(15,23,42,.07)}figcaption{display:flex;flex-wrap:wrap;justify-content:space-between;gap:4px 16px;align-items:baseline;font-weight:750;padding:2px 8px 12px}figcaption small{color:#64748b;font-weight:600}figcaption .note{flex-basis:100%;margin:0;color:#475569;font-size:.85rem;font-weight:500}svg{display:block;width:100%;height:auto}.denominator{margin:0;color:#334155}.table-wrap{overflow:auto}table{border-collapse:collapse;width:100%;font-size:.84rem}th,td{text-align:left;vertical-align:top;padding:9px;border-bottom:1px solid #e2e8f0}th{color:#475569;font-size:.75rem;text-transform:uppercase;letter-spacing:.04em}code{font-size:.78rem;overflow-wrap:anywhere}.panel .note{margin:0 0 12px;color:#475569;font-size:.85rem}td.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}.decision{display:inline-block;border-radius:999px;padding:3px 9px;font-size:.75rem;font-weight:700;border:1px solid currentColor}.decision-faster{background:#dcfce7;color:#166534}.decision-slower{background:#fee2e2;color:#991b1b}.decision-equivalent{background:#e2e8f0;color:#334155}.decision-unknown{background:#fef3c7;color:#92400e}.decision-invalid{background:#f3e8ff;color:#6b21a8}.reason{display:block;margin-top:4px;color:#64748b;font-size:.75rem}@media(max-width:640px){.shell{width:min(100% - 16px,1200px);padding-top:24px}.panel,figure{padding:8px;border-radius:12px}figcaption{align-items:flex-start;flex-direction:column}}</style></head><body><main class=\"shell\"><header><h1>mare_mark report</h1><div class=\"meta\"><span class=\"tag\">Run " +
  escape_xml(document.run_id) +
  "</span><span class=\"tag\">Target " +
  escape_xml(document.target) +
  "</span><span class=\"tag\">Schema " +
  escape_xml(document.schema_version.identifier()) +
  "</span></div></header>" +
  differential_html(document.differential) +
  comparisons_html(document.comparisons) +
  figures +
  "</main></body></html>"
}

///|
/// Bootstrap resamples per comparison. The stats design asks for at least
/// 1000 at 95 %; 10000 puts the Monte Carlo error of each endpoint near 0.16
/// percentage points of the 2.5 % tail mass and costs O(10000 n log n).
const COMPARISON_RESAMPLES : Int = 10000

///|
/// Fewest used blocks for which a comparison is decided. With one or two
/// pairs the median is the mean of the pairs and the percentile interval is
/// the range of the data, so neither says anything about the spread.
const COMPARISON_MIN_BLOCKS : Int = 3

///|
/// Confidence of the bootstrap interval, in percent.
let comparison_confidence_pct : Double = 95.0

///|
/// What the comparisons of a report are computed with, and where each value
/// comes from.
priv struct ComparisonSettings {
  practical_delta_pct : Double
  outlier_policy : @model.OutlierPolicy
  run_seed : UInt64
  protocol_recorded : Bool
  seed_recorded : Bool
}

///|
/// The recorded protocol and seed, or the defaults of `ReportOnly`, a 1 %
/// threshold and seed 0 for records written without them.
fn comparison_settings(
  protocol : @model.RunProtocol?,
  run_seed : UInt64?,
) -> ComparisonSettings {
  let (practical_delta_pct, outlier_policy) = match protocol {
    Some(protocol) => (protocol.practical_delta_pct, protocol.outlier_policy)
    None => (1.0, @model.OutlierPolicy::ReportOnly)
  }
  {
    practical_delta_pct,
    outlier_policy,
    run_seed: run_seed.unwrap_or(0UL),
    protocol_recorded: protocol is Some(_),
    seed_recorded: run_seed is Some(_),
  }
}

///|
/// Parses the canonical decimal text of a `UInt64`, as written by the JSONL
/// summary.
fn decimal_uint64(text : String) -> UInt64? {
  let value = try @string.parse_uint64(text, base=10) catch {
    _ => return None
  } noraise {
    value => value
  }
  if value.to_string() == text {
    Some(value)
  } else {
    None
  }
}

///|
/// Bootstrap seed of one comparison row: 64-bit FNV-1a over the UTF-16 code
/// units of `mare_mark/compare/v1`, the decimal run seed, the case, the scale,
/// the baseline and the candidate, separated by U+001F. The same record gives
/// the same seed on every target, and rows never share a resampling stream.
fn comparison_seed(
  run_seed : UInt64,
  case_id : String,
  scale : String,
  baseline : String,
  candidate : String,
) -> UInt64 {
  let text = [
    "mare_mark/compare/v1",
    run_seed.to_string(),
    case_id,
    scale,
    baseline,
    candidate,
  ].join("\u{1f}")
  let mut hash = 0xCBF29CE484222325UL
  for index = 0; index < text.length(); index = index + 1 {
    hash = (hash ^ text[index].to_int().to_uint64()) * 0x100000001B3UL
  }
  hash
}

///|
/// The confirmatory times of `group` by block, in order of first appearance.
/// Entries without a block id are left out.
fn block_times(group : TimingGroup?) -> Map[Int, Array[Double]] {
  let blocks : Map[Int, Array[Double]] = Map([])
  guard group is Some(group) else { return blocks }
  for index = 0; index < group.elapsed_us.length(); index = index + 1 {
    guard group.block_ids[index] is Some(block) else { continue }
    match blocks.get(block) {
      Some(values) => values.push(group.elapsed_us[index])
      None => blocks[block] = [group.elapsed_us[index]]
    }
  }
  blocks
}

///|
/// The complete blocks of a baseline and a candidate group, as
/// `(block, baseline, candidate)` in ascending block order, and the number of
/// blocks seen in either group that are not complete. A block is complete when
/// it holds exactly one observation of each implementation.
fn paired_blocks(
  baseline : TimingGroup?,
  candidate : TimingGroup,
) -> (Array[(Int, Double, Double)], Int) {
  let baseline_blocks = block_times(baseline)
  let candidate_blocks = block_times(Some(candidate))
  let blocks : Array[Int] = []
  for block, _ in baseline_blocks {
    blocks.push(block)
  }
  for block, _ in candidate_blocks {
    if !baseline_blocks.contains(block) {
      blocks.push(block)
    }
  }
  blocks.sort()
  let pairs = []
  let mut incomplete = 0
  for block in blocks {
    match (baseline_blocks.get(block), candidate_blocks.get(block)) {
      (Some([baseline_us]), Some([candidate_us])) =>
        pairs.push((block, baseline_us, candidate_us))
      _ => incomplete += 1
    }
  }
  (pairs, incomplete)
}

///|
/// Applies `policy` to the paired deltas `candidate - baseline` and keeps the
/// pairs whose delta survives. `@stats.filter_outliers` keeps a value when it
/// lies inside fences computed from all values, so whether a pair survives
/// depends only on its delta, and membership in the filtered deltas
/// identifies the surviving pairs exactly.
fn filter_pairs(
  pairs : Array[(Int, Double, Double)],
  policy : @model.OutlierPolicy,
) -> Array[(Int, Double, Double)] {
  if policy is ReportOnly {
    return pairs.copy()
  }
  // `filter_outliers` keeps or drops a value by the value alone, so membership
  // of a delta in its result decides the pair. A `NaN` delta is never kept by
  // the fences, and `contains` would not find it anyway (`NaN != NaN`).
  let deltas = pairs.map(pair => pair.2 - pair.1)
  let kept = @stats.filter_outliers(deltas, policy)
  pairs.filter(pair => kept.contains(pair.2 - pair.1))
}

///|
fn decision_of(decision : @stats.Decision) -> @ir.ComparisonDecision {
  match decision {
    Faster => @ir.ComparisonDecision::Faster
    Slower => @ir.ComparisonDecision::Slower
    Equivalent => @ir.ComparisonDecision::Equivalent
    Invalid => @ir.ComparisonDecision::Invalid
    Unknown => @ir.ComparisonDecision::Unknown
  }
}

///|
fn bootstrap_error_text(error : @stats.BootstrapError) -> String {
  match error {
    EmptySamples => "no paired deltas"
    MismatchedPairs(baseline, candidate) =>
      "mismatched pairs (" +
      baseline.to_string() +
      " baseline, " +
      candidate.to_string() +
      " candidate)"
    InvalidResamples(count) => "invalid resample count " + count.to_string()
    InvalidConfidence(value) => "invalid confidence " + value.to_string()
    NonFiniteSample(index) =>
      "paired delta " + index.to_string() + " is not finite"
  }
}

///|
fn plural(count : Int, singular : String, many : String) -> String {
  count.to_string() + " " + (if count == 1 { singular } else { many })
}

///|
/// The comparison of `candidate` against `baseline` at one scale of one case.
fn compare_groups(
  case_id : String,
  scale : String,
  baseline_id : String,
  baseline : TimingGroup?,
  candidate : TimingGroup,
  settings : ComparisonSettings,
) -> @ir.ComparisonRow {
  let seed = comparison_seed(
    settings.run_seed,
    case_id,
    scale,
    baseline_id,
    candidate.implementation,
  )
  let (pairs, incomplete) = paired_blocks(baseline, candidate)
  let used = filter_pairs(pairs, settings.outlier_policy)
  let baseline_us = used.map(pair => pair.1)
  let candidate_us = used.map(pair => pair.2)
  let estimate = if used.is_empty() {
    None
  } else {
    let point = @stats.compare_paired(
      baseline_id,
      candidate.implementation,
      baseline_us,
      candidate_us,
      settings.practical_delta_pct,
      @model.confirmatory_interval(),
    )
    Some(
      @ir.PairedEstimate::new(
        @stats.summarize(baseline_us).median,
        @stats.summarize(candidate_us).median,
        @stats.summarize(@stats.paired_deltas(baseline_us, candidate_us)).median,
        point.relative_delta_pct,
        point.speedup,
      ),
    )
  }
  let row = (
    decision : @ir.ComparisonDecision,
    reason : String,
    interval : @ir.DeltaInterval?,
  ) => {
    @ir.ComparisonRow::new(
      case_id,
      scale,
      baseline_id,
      candidate.implementation,
      decision,
      reason,
      estimate,
      interval,
      used.length(),
      incomplete,
      pairs.length() - used.length(),
      seed,
    )
  }
  let recorded_blocks = candidate.block_ids.any(block => block is Some(_)) ||
    (baseline is Some(group) && group.block_ids.any(block => block is Some(_)))
  if !recorded_blocks {
    return row(
      Unknown,
      "block_id not recorded; observations cannot be paired",
      None,
    )
  }
  if baseline is None {
    return row(
      Unknown,
      "baseline has no confirmatory observations at this scale",
      None,
    )
  }
  if used.length() < COMPARISON_MIN_BLOCKS {
    return row(
      Unknown,
      plural(used.length(), "usable block", "usable blocks") +
      "; at least " +
      COMPARISON_MIN_BLOCKS.to_string() +
      " are needed",
      None,
    )
  }
  let baseline_median = @stats.summarize(baseline_us).median
  if !(baseline_median > 0.0) {
    return row(
      Invalid,
      "baseline median is not positive; the relative delta is undefined",
      None,
    )
  }
  match
    @stats.compare_paired_with_bootstrap(
      baseline_id,
      candidate.implementation,
      baseline_us,
      candidate_us,
      settings.practical_delta_pct,
      @model.confirmatory_interval(),
      seed,
      COMPARISON_RESAMPLES,
      comparison_confidence_pct,
    ) {
    Ok(comparison) => {
      let interval = @ir.DeltaInterval::new(
        comparison.interval.low,
        comparison.interval.high,
        comparison.interval.low / baseline_median * 100.0,
        comparison.interval.high / baseline_median * 100.0,
      )
      let decision = decision_of(comparison.decision)
      let reason = if decision is Invalid {
        "practical_delta_pct " +
        settings.practical_delta_pct.to_string() +
        " is not a finite, non-negative threshold"
      } else {
        ""
      }
      row(decision, reason, Some(interval))
    }
    Err(error) =>
      row(Invalid, "bootstrap: " + bootstrap_error_text(error), None)
  }
}

///|
/// The comparisons of one case: at every scale, every implementation measured
/// there against the baseline, in order of first appearance.
fn case_comparisons(
  timings : CaseTimings,
  baseline : String?,
  settings : ComparisonSettings,
) -> Array[@ir.ComparisonRow] {
  let baseline_id = match baseline {
    Some(id) => id
    None =>
      match timings.implementations {
        [first, ..] => first
        [] => return []
      }
  }
  let rows = []
  let scales : Array[(String, ScaleSource)] = []
  for group in timings.groups {
    let key = (group.scale, group.scale_source)
    if !scales.contains(key) {
      scales.push(key)
    }
  }
  for key in scales {
    let groups = timings.groups.filter(group => {
      group.scale == key.0 && group.scale_source == key.1
    })
    let baseline_group = match
      groups.search_by(group => group.implementation == baseline_id) {
      Some(index) => Some(groups[index])
      None => None
    }
    let scale = match key.1 {
      Recorded => key.0
      DatasetId => "dataset_id " + key.0
    }
    for group in groups {
      if group.implementation != baseline_id {
        rows.push(
          compare_groups(
            timings.case_id,
            scale,
            baseline_id,
            baseline_group,
            group,
            settings,
          ),
        )
      }
    }
  }
  rows
}

///|
fn comparison_note(settings : ComparisonSettings, unpaired : Int) -> String {
  let threshold = "threshold ±" +
    format_number(settings.practical_delta_pct) +
    " % and outlier policy " +
    settings.outlier_policy.text() +
    " (applied to the paired deltas)"
  let protocol = if settings.protocol_recorded {
    "Decision " + threshold + " from the recorded protocol"
  } else {
    "The record has no protocol: decision " + threshold + " are defaults"
  }
  let seed = if settings.seed_recorded {
    "run seed " + settings.run_seed.to_string() + " from the record"
  } else {
    "the record has no seed: run seed " +
    settings.run_seed.to_string() +
    " is a default"
  }
  protocol +
  "; " +
  seed +
  ". Each row pairs the confirmatory observations of one block, needs at least " +
  COMPARISON_MIN_BLOCKS.to_string() +
  " usable blocks, and reports a " +
  format_number(comparison_confidence_pct) +
  " % percentile bootstrap interval of the median paired delta with " +
  COMPARISON_RESAMPLES.to_string() +
  " resamples (report defaults), seeded from the run seed, case, scale, baseline and candidate; with few blocks its actual coverage can be well below the nominal level." +
  (if unpaired == 0 {
    ""
  } else {
    " " +
    plural(
      unpaired, "confirmatory observation has", "confirmatory observations have",
    ) +
    " no block_id and cannot be paired."
  })
}

///|
fn comparison_report(
  timings : Array[CaseTimings],
  baseline : String?,
  settings : ComparisonSettings,
) -> @ir.ComparisonReport {
  let rows = []
  let mut unpaired = 0
  for case_timings in timings {
    rows.append(case_comparisons(case_timings, baseline, settings))
    for group in case_timings.groups {
      unpaired += group.block_ids.filter(block => block is None).length()
    }
  }
  @ir.ComparisonReport::new(
    rows,
    settings.practical_delta_pct,
    settings.outlier_policy.text(),
    comparison_confidence_pct,
    COMPARISON_RESAMPLES,
    COMPARISON_MIN_BLOCKS,
    settings.run_seed,
    settings.protocol_recorded,
    settings.seed_recorded,
    comparison_note(settings, unpaired),
  )
}

///|
fn decision_label(decision : @ir.ComparisonDecision) -> String {
  match decision {
    Faster => "Faster"
    Slower => "Slower"
    Equivalent => "Equivalent"
    Unknown => "Unknown"
    Invalid => "Invalid"
  }
}

///|
/// `value` rounded to three decimals with an explicit sign; zero has none.
fn signed_number(value : Double) -> String {
  if value > 0.0 {
    "+" + format_number(value)
  } else if value == 0.0 {
    "0"
  } else {
    format_number(value)
  }
}

///|
/// The cells of one comparison row as plain text, in table order: case, scale,
/// baseline, candidate, the two medians, the relative delta, the interval,
/// the decision, the blocks used / incomplete / outliers, the seed and the
/// reason.
fn comparison_cells(row : @ir.ComparisonRow) -> Array[String] {
  let (baseline_median, candidate_median, delta) = match row.estimate {
    Some(estimate) =>
      (
        format_number(estimate.baseline_median_us),
        format_number(estimate.candidate_median_us),
        signed_number(estimate.relative_delta_pct) + " %",
      )
    None => ("-", "-", "-")
  }
  let interval = match row.interval {
    Some(interval) =>
      "[" +
      signed_number(interval.low_pct) +
      " %, " +
      signed_number(interval.high_pct) +
      " %]"
    None => "-"
  }
  [
    row.case_id,
    row.scale,
    row.baseline,
    row.candidate,
    baseline_median,
    candidate_median,
    delta,
    interval,
    decision_label(row.decision),
    row.blocks_used.to_string() +
    " / " +
    row.blocks_incomplete.to_string() +
    " / " +
    row.blocks_outliers.to_string(),
    row.seed.to_string(),
    row.reason,
  ]
}

///|
fn comparison_headers(report : @ir.ComparisonReport) -> Array[String] {
  [
    "Case",
    "Scale",
    "Baseline",
    "Candidate",
    "Baseline µs/op",
    "Candidate µs/op",
    "Delta",
    format_number(report.confidence_pct) + " % interval",
    "Decision",
    "Blocks used / incomplete / outliers",
    "Seed",
    "Reason",
  ]
}

///|
fn comparisons_html(report : @ir.ComparisonReport) -> String {
  if report.rows.is_empty() {
    return ""
  }
  let numeric = [
    false, false, false, false, true, true, true, true, false, true, false,
  ]
  let header = comparison_headers(report).map(text => {
    "<th scope=\"col\">" + escape_xml(text) + "</th>"
  })
  header.remove(header.length() - 1) |> ignore
  let rows = report.rows
    .map(row => {
      let cells = comparison_cells(row)
      let mut body = "<tr>"
      for index = 0; index < numeric.length(); index = index + 1 {
        if index == 8 {
          let name = row.decision.text()
          body += "<td><span class=\"decision decision-" +
            name +
            "\">" +
            escape_xml(cells[index]) +
            "</span>" +
            (if row.reason.is_empty() {
              ""
            } else {
              "<span class=\"reason\">" + escape_xml(row.reason) + "</span>"
            }) +
            "</td>"
        } else if index == 10 {
          body += "<td><code>" + escape_xml(cells[index]) + "</code></td>"
        } else {
          body += (if numeric[index] { "<td class=\"num\">" } else { "<td>" }) +
            escape_xml(cells[index]) +
            "</td>"
        }
      }
      body + "</tr>"
    })
    .join("\n")
  "<section class=\"panel\" aria-labelledby=\"comparisons-title\"><h2 id=\"comparisons-title\">Comparisons</h2><p class=\"note\">" +
  escape_xml(report.note) +
  "</p><div class=\"table-wrap\"><table><thead><tr>" +
  header.join("") +
  "</tr></thead><tbody>" +
  rows +
  "</tbody></table></div></section>"
}

///|
/// The comparisons of `document` as an aligned plain-text table preceded by
/// the settings note, or `""` when there are none. `mare-mark report` prints
/// it next to the HTML.
pub fn comparisons_text(document : @ir.PlotDocument) -> String {
  let report = document.comparisons
  if report.rows.is_empty() {
    return ""
  }
  let table = [comparison_headers(report).map(text => text.to_lower())]
  for row in report.rows {
    table.push(comparison_cells(row))
  }
  let columns = table[0].length()
  let widths = Array::makei(columns, column => {
    table.fold(init=0, (width, cells) => width.max(cells[column].length()))
  })
  let lines = table.map(cells => {
    let mut line = ""
    for column = 0; column < columns; column = column + 1 {
      let cell = cells[column]
      line += if column == columns - 1 {
        cell
      } else {
        cell + " ".repeat(widths[column] - cell.length() + 2)
      }
    }
    line.trim_end().to_owned()
  })
  "Comparisons\n" + report.note + "\n" + lines.join("\n")
}
