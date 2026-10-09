///|
test "report escapes structured output" {
  let plot = @ir.Plot::new(
    @ir.PlotKind::Scaling,
    "A < B & C",
    "µs/op",
    "raw",
    [
      @ir.PlotPoint::new("1", 10.0, "base\"line"),
      @ir.PlotPoint::new("2", 8.0, "base\"line"),
    ],
  )
  let document = @ir.PlotDocument::new("run<&", "native", [plot])
  let svg = plot_svg(plot)
  let json = plot_json(document)
  let page = html(document)
  assert_true(svg.contains("A &lt; B &amp; C"))
  assert_true(svg.contains("<polyline"))
  assert_true(json.contains("base\\\"line"))
  assert_true(page.contains("run&lt;&amp;"))
  assert_true(json.contains("\"schema_version\":\"mmks_2\""))
  assert_true(page.contains("<h1>mare_mark report</h1>"))
}

///|
test "report parses observation JSONL into plot IR" {
  let source = "{\"type\":\"observation\",\"implementation\":\"baseline\",\"dataset_id\":4,\"elapsed_us\":12.5,\"iterations\":1}\n" +
    "{\"type\":\"summary\",\"run_id\":\"demo\",\"observation_count\":1}"
  match document_from_jsonl(source, target="native") {
    Ok(document) => {
      assert_eq(document.run_id, "demo")
      assert_eq(document.target, "native")
      assert_eq(document.plots[0].points.length(), 1)
      assert_eq(document.plots[0].points[0].y, 12.5)
    }
    Err(message) => abort(message)
  }
}

///|
test "report excludes observations for failed benchmark keys" {
  let source = "{\"type\":\"observation\",\"case\":\"vector_add\",\"implementation\":\"candidate\",\"dataset_id\":1,\"elapsed_us\":1.0,\"valid\":true,\"batch_sink\":\"kept\"}\n" +
    "{\"type\":\"observation\",\"case\":\"vector_add\",\"implementation\":\"candidate\",\"dataset_id\":2,\"elapsed_us\":2.0,\"valid\":true,\"batch_sink\":\"kept\"}\n" +
    "{\"type\":\"observation\",\"case\":\"vector_add\",\"implementation\":\"baseline\",\"dataset_id\":1,\"elapsed_us\":3.0,\"valid\":true,\"batch_sink\":\"kept\"}\n" +
    "{\"type\":\"observation\",\"case\":\"vector_add\",\"implementation\":\"candidate\",\"dataset_id\":3,\"elapsed_us\":4.0,\"valid\":false,\"batch_sink\":\"kept\"}\n" +
    "{\"type\":\"observation\",\"case\":\"vector_add\",\"implementation\":\"candidate\",\"dataset_id\":4,\"elapsed_us\":5.0,\"valid\":true,\"batch_sink\":\"discarded:outlier\"}\n" +
    "{\"type\":\"validation\",\"status\":\"invalid\",\"case\":\"vector_add\",\"implementation\":\"candidate\",\"dataset_id\":1}"
  match document_from_jsonl(source) {
    Ok(document) => {
      let points = document.plots[0].points
      assert_eq(points.length(), 2)
      assert_true(
        points.any(point => {
          point.series == "candidate" && point.x == "2" && point.y == 2.0
        }),
      )
      assert_true(
        points.any(point => {
          point.series == "baseline" && point.x == "1" && point.y == 3.0
        }),
      )
      assert_true(
        !points.any(point => point.series == "candidate" && point.x == "1"),
      )
    }
    Err(message) => abort(message)
  }
}

///|
test "report rejects invalid or empty event streams" {
  assert_true(document_from_jsonl("not-json") is Err(_))
  assert_true(
    document_from_jsonl("{\"type\":\"summary\",\"run_id\":\"empty\"}") is Err(_),
  )
  assert_true(
    document_from_jsonl(
      "{\"artifact_version\":\"mmka_99\",\"type\":\"observation\"}",
    )
    is Err("unsupported artifact version 'mmka_99' at line 1"),
  )
}

///|
test "heatmap uses cells instead of scatter marks" {
  let plot = @ir.Plot::new(
    @ir.PlotKind::Heatmap,
    "Tile search",
    "µs/op",
    "median",
    [
      @ir.PlotPoint::new("64x64", 10.0, "4x4"),
      @ir.PlotPoint::new("128x128", 20.0, "4x4"),
    ],
  )
  assert_true(plot_svg(plot).contains("<rect"))
  let numeric_heatmap = @ir.Plot::new(
    @ir.PlotKind::Heatmap,
    "Numeric heatmap",
    "µs/op",
    "median",
    [@ir.PlotPoint::new("1", 1.0, "a"), @ir.PlotPoint::new("1000", 4.0, "b")],
    x_axis=@ir.AxisScale::Log,
  )
  assert_true(!uses_log_x(numeric_heatmap))
  assert_true(plot_svg(numeric_heatmap).contains(">1</text>"))
}

///|
test "differential report includes mismatches capabilities and counterexamples" {
  let source = "{\"type\":\"validation\",\"status\":\"invalid\",\"implementation\":\"decimal-community\",\"operation\":\"divide\",\"operands\":[\"1\",\"0\"],\"expected\":\"Infinity\",\"actual\":\"aborted\",\"expected_flags\":[\"division_by_zero\"],\"actual_flags\":[],\"actual_kind\":\"aborted\",\"trap\":\"\",\"fingerprint\":\"sha256:abc\",\"replay_command\":\"decimal-worker\"}\n" +
    "{\"type\":\"validation_failure\",\"implementation\":\"decimal-community\",\"minimal_input\":\"1 / 0\",\"minimal_fingerprint\":\"sha256:def\",\"shrink_path\":[\"10 / 0\",\"1 / 0\"],\"replay_command\":\"decimal-worker\"}\n" +
    "{\"type\":\"summary\",\"run_id\":\"diff\",\"passed_count\":8,\"failed_count\":1,\"unsupported_count\":2,\"expected_difference_count\":1}"
  match document_from_jsonl(source) {
    Ok(document) => {
      assert_eq(document.differential.mismatches.length(), 1)
      assert_eq(document.differential.capabilities.length(), 1)
      assert_eq(document.differential.counterexamples.length(), 1)
      assert_eq(document.differential.corpus.total, 12)
      let page = html(document)
      assert_true(page.contains("Flags diff"))
      assert_true(page.contains("Capability coverage matrix"))
      assert_true(page.contains("Minimal counterexamples"))
    }
    Err(message) => abort(message)
  }
}

///|
test "every plot kind renders a non-empty SVG" {
  let kinds = [
    @ir.PlotKind::Scaling,
    @ir.PlotKind::RawDistribution,
    @ir.PlotKind::BlockOrder,
    @ir.PlotKind::Interval,
    @ir.PlotKind::Outlier,
    @ir.PlotKind::ChangePoint,
    @ir.PlotKind::Heatmap,
    @ir.PlotKind::Pareto,
  ]
  for kind in kinds {
    let plot = @ir.Plot::new(kind, "plot", "unit", "interval", [
      @ir.PlotPoint::new("1", 1.0, "a"),
      @ir.PlotPoint::new("2", 2.0, "b"),
    ])
    assert_true(plot_svg(plot).length() > 0)
  }
}

///|
fn point_texts(plot : @ir.Plot) -> Array[String] {
  plot.points.map(point => {
    point.series + "@" + point.x + "=" + point.y.to_string()
  })
}

///|
test "exploratory observations stay out of the confirmatory plot (#7)" {
  let source =
    #|{"type":"observation","case":"matmul","implementation":"naive","dataset_id":7,"phase":"exploratory","elapsed_us":900.0,"valid":true}
    #|{"type":"observation","case":"matmul","implementation":"naive","dataset_id":7,"phase":"confirmatory","elapsed_us":100.0,"valid":true}
  guard document_from_jsonl(source) is Ok(document) else {
    abort("expected a document")
  }
  assert_eq(document.plots.length(), 1)
  let plot = document.plots[0]
  assert_eq(plot.title, "Benchmark observations: matmul")
  assert_eq(plot.interval_kind, "median")
  assert_true(point_texts(plot) == ["naive@7=100"])
  assert_eq(plot.x_label, "dataset_id (scale not recorded)")
  assert_true(plot.note.contains("Excluded: 1 exploratory observation."))
  // With the scale recorded, the x value is the scale, not the dataset index.
  let scaled =
    #|{"type":"observation","case":"matmul","implementation":"naive","dataset_id":7,"scale":"256","phase":"exploratory","elapsed_us":900.0,"valid":true}
    #|{"type":"observation","case":"matmul","implementation":"naive","dataset_id":7,"scale":"256","phase":"confirmatory","elapsed_us":100.0,"valid":true}
  guard document_from_jsonl(scaled) is Ok(document) else {
    abort("expected a document")
  }
  let plot = document.plots[0]
  assert_true(point_texts(plot) == ["naive@256=100"])
  assert_eq(plot.x_label, "scale")
  assert_true(plot.x_axis is @ir.AxisScale::Linear)
  let svg = plot_svg(plot)
  assert_true(!svg.contains("900"))
  assert_true(svg.contains(">256</text>"))
  assert_true(svg.contains(">scale</text>"))
}

///|
test "numeric scales use a linear axis in numeric order" {
  let source =
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":0,"scale":"99","phase":"confirmatory","elapsed_us":30.0}
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":1,"scale":"10","phase":"confirmatory","elapsed_us":1.0}
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":2,"scale":"50","phase":"confirmatory","elapsed_us":4.0}
  guard document_from_jsonl(source) is Ok(document) else {
    abort("expected a document")
  }
  let plot = document.plots[0]
  assert_true(plot.x_axis is @ir.AxisScale::Linear)
  let (x_values, positions, labelled) = x_layout(plot)
  assert_true(x_values == ["10", "50", "99"])
  assert_eq(positions[0], 76.0)
  assert_eq(positions[2], 880.0)
  // 50 is slightly before the midpoint on a 10..99 linear axis.
  assert_true(positions[1] > 430.0 && positions[1] < 440.0)
  assert_true(labelled == [true, true, true])
  assert_true(log_ticks(1.0, 10.0) == [1.0, 2.0, 5.0, 10.0])
  assert_true(has_log_span([1.0, 100.0]))
  assert_true(!has_log_span([1.0, 99.0]))
  let svg = plot_svg(plot)
  assert_true(svg.contains("<polyline"))
  assert_true(svg.contains("points=\"76,"))
}

///|
test "wide numeric scales use a logarithmic axis without squeezing small scales" {
  let source =
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":0,"scale":"10000","phase":"confirmatory","elapsed_us":30.0}
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":1,"scale":"1","phase":"confirmatory","elapsed_us":1.0}
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":2,"scale":"100","phase":"confirmatory","elapsed_us":4.0}
  guard document_from_jsonl(source) is Ok(document) else {
    abort("expected a document")
  }
  let plot = document.plots[0]
  assert_true(plot.x_axis is @ir.AxisScale::Log)
  assert_true(plot.y_axis is @ir.AxisScale::Linear)
  let (x_values, positions, labelled) = x_layout(plot)
  assert_true(x_values == ["1", "100", "10000"])
  assert_eq(positions[0], 76.0)
  assert_eq(positions[2], 880.0)
  assert_true(positions[1] > 475.0 && positions[1] < 481.0)
  assert_true(labelled == [true, true, true])
  let svg = plot_svg(plot)
  assert_true(svg.contains("scale (log₁₀)"))
  assert_true(svg.contains("X uses a base-10 logarithmic axis."))
  let json = plot_json(document)
  assert_true(json.contains("\"x_axis\":\"log\",\"y_axis\":\"linear\""))
}

///|
test "scaling plot selects logarithmic y independently for wide positive values" {
  let source =
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":0,"scale":"1","phase":"confirmatory","elapsed_us":0.01}
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":1,"scale":"2","phase":"confirmatory","elapsed_us":1.0}
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":2,"scale":"3","phase":"confirmatory","elapsed_us":10.0}
  guard document_from_jsonl(source) is Ok(document) else {
    abort("expected a document")
  }
  let plot = document.plots[0]
  assert_true(plot.x_axis is @ir.AxisScale::Linear)
  assert_true(plot.y_axis is @ir.AxisScale::Log)
  let svg = plot_svg(plot)
  assert_true(svg.contains("µs/op (log₁₀)"))
  assert_true(svg.contains("Y uses a base-10 logarithmic axis."))
  assert_true(svg.contains(">0.01</text>"))
  assert_true(svg.contains(">1</text>"))
  let equal_multiplicative_steps = @ir.Plot::new(
    @ir.PlotKind::Scaling,
    "equal ratios",
    "µs/op",
    "median",
    [
      @ir.PlotPoint::new("a", 1.0, "loop"),
      @ir.PlotPoint::new("b", 100.0, "loop"),
      @ir.PlotPoint::new("c", 10000.0, "loop"),
    ],
    y_axis=@ir.AxisScale::Log,
  )
  assert_true(uses_log_y(equal_multiplicative_steps))
  assert_eq(
    y_transform(equal_multiplicative_steps, 100.0) -
    y_transform(equal_multiplicative_steps, 1.0),
    y_transform(equal_multiplicative_steps, 10000.0) -
    y_transform(equal_multiplicative_steps, 100.0),
  )
}

///|
test "wide-axis automatic log selection falls back for non-positive and narrow data" {
  assert_true(!has_log_span([]))
  assert_true(!has_log_span([5.0, 5.0]))
  assert_true(!has_log_span([0.0, 1000.0]))
  assert_true(!has_log_span([-1.0, 1000.0]))
  assert_true(!has_log_span([@math.log10(-1.0), 1000.0]))
  assert_true(!has_log_span([@math.pow(10.0, 400.0), 1000.0]))
  let non_positive = @ir.Plot::new(
    @ir.PlotKind::Scaling,
    "non-positive",
    "µs/op",
    "median",
    [
      @ir.PlotPoint::new("0", 1.0, "loop"),
      @ir.PlotPoint::new("1000", -2.0, "loop"),
    ],
    x_axis=@ir.AxisScale::Linear,
    y_axis=@ir.AxisScale::Linear,
  )
  assert_true(!uses_log_x(non_positive))
  assert_true(!uses_log_y(non_positive))
  let narrow = @ir.Plot::new(
    @ir.PlotKind::Scaling,
    "narrow",
    "µs/op",
    "median",
    [
      @ir.PlotPoint::new("10", 10.0, "loop"),
      @ir.PlotPoint::new("90", 90.0, "loop"),
    ],
    x_axis=@ir.AxisScale::Log,
    y_axis=@ir.AxisScale::Log,
  )
  assert_true(uses_log_x(narrow))
  assert_true(uses_log_y(narrow))
  let narrow_auto =
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":0,"scale":"10","phase":"confirmatory","elapsed_us":10.0}
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":1,"scale":"90","phase":"confirmatory","elapsed_us":90.0}
  guard document_from_jsonl(narrow_auto) is Ok(document) else {
    abort("expected a document")
  }
  assert_true(document.plots[0].x_axis is @ir.AxisScale::Linear)
  assert_true(document.plots[0].y_axis is @ir.AxisScale::Linear)
  let independent_fallback =
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":0,"scale":"0","phase":"confirmatory","elapsed_us":1.0}
    #|{"type":"observation","case":"sum","implementation":"loop","dataset_id":1,"scale":"10000","phase":"confirmatory","elapsed_us":1000.0}
  guard document_from_jsonl(independent_fallback) is Ok(document) else {
    abort("expected a document")
  }
  assert_true(document.plots[0].x_axis is @ir.AxisScale::Linear)
  assert_true(document.plots[0].y_axis is @ir.AxisScale::Log)
}

///|
test "non-numeric scales are categorical in order of first appearance" {
  let source =
    #|{"type":"observation","case":"sort","implementation":"merge","dataset_id":0,"scale":"small","phase":"confirmatory","elapsed_us":1.0}
    #|{"type":"observation","case":"sort","implementation":"merge","dataset_id":1,"scale":"large","phase":"confirmatory","elapsed_us":9.0}
    #|{"type":"observation","case":"sort","implementation":"quick","dataset_id":2,"scale":"medium","phase":"confirmatory","elapsed_us":4.0}
    #|{"type":"observation","case":"sort","implementation":"quick","dataset_id":0,"scale":"small","phase":"confirmatory","elapsed_us":2.0}
  guard document_from_jsonl(source) is Ok(document) else {
    abort("expected a document")
  }
  let plot = document.plots[0]
  assert_true(plot.x_axis is @ir.AxisScale::Categorical)
  let (x_values, positions, _) = x_layout(plot)
  assert_true(x_values == ["small", "large", "medium"])
  assert_true(positions == [76.0, 478.0, 880.0])
  assert_true(plot_svg(plot).contains(">large</text>"))
}

///|
test "datasets sharing a scale are pooled into one median" {
  let source =
    #|{"type":"observation","case":"fft","implementation":"radix2","dataset_id":0,"block_id":1,"scale":"64","phase":"confirmatory","elapsed_us":1.0}
    #|{"type":"observation","case":"fft","implementation":"radix2","dataset_id":0,"block_id":2,"scale":"64","phase":"confirmatory","elapsed_us":5.0}
    #|{"type":"observation","case":"fft","implementation":"radix2","dataset_id":1,"block_id":1,"scale":"64","phase":"confirmatory","elapsed_us":3.0}
    #|{"type":"observation","case":"fft","implementation":"radix2","dataset_id":1,"block_id":2,"scale":"64","phase":"confirmatory","elapsed_us":4.0}
    #|{"type":"observation","case":"fft","implementation":"radix2","dataset_id":2,"block_id":1,"scale":"128","phase":"confirmatory","elapsed_us":7.0}
    #|{"type":"observation","case":"fft","implementation":"radix2","dataset_id":2,"block_id":0,"scale":"128","phase":"exploratory","elapsed_us":70.0}
  guard document_from_jsonl(source) is Ok(document) else {
    abort("expected a document")
  }
  assert_true(
    point_texts(document.plots[0]) == ["radix2@64=3.5", "radix2@128=7"],
  )
  assert_true(
    document.plots[0].note.contains(
      "pooled over every dataset and repetition at that scale.",
    ),
  )
}

///|
test "confirmatory timings group by case, scale and implementation" {
  let observation = (
    case_id : String,
    implementation : String,
    dataset_id : Int,
    phase : String,
    scale : String?,
    elapsed_us : Double,
  ) => {
    case_id,
    implementation,
    dataset_id,
    phase,
    scale,
    block_id: None,
    elapsed_us,
  }
  let observations = [
    observation("a", "x", 0, "confirmatory", Some("8"), 1.0),
    observation("a", "y", 0, "confirmatory", Some("8"), 2.0),
    observation("b", "x", 0, "", None, 3.0),
    observation("a", "x", 1, "confirmatory", Some("8"), 4.0),
    observation("a", "x", 2, "exploratory", Some("8"), 5.0),
    observation("a", "x", 3, "warmup", Some("16"), 6.0),
    observation("a", "y", 4, "confirmatory", Some("16"), 7.0),
    observation("a", "x", 5, "confirmatory", None, 8.0),
    observation("a", "y", 6, "confirmatory", Some("16"), 9.0),
  ]
  let failures = [{ case_id: "a", implementation: "y", dataset_id: 6, }]
  let cases = confirmatory_timings(observations, failures)
  assert_true(cases.map(item => item.case_id) == ["a", "b"])
  let groups = cases[0].groups
  assert_true(
    groups.map(group => group.implementation + "@" + group.scale) ==
    ["x@8", "y@8", "y@16", "x@5"],
  )
  assert_true(groups[0].elapsed_us == [1.0, 4.0])
  assert_true(groups[2].elapsed_us == [7.0])
  assert_true(groups[3].scale_source == DatasetId)
  assert_eq(cases[0].excluded_by_phase.get("exploratory"), Some(1))
  assert_eq(cases[0].excluded_by_phase.get("warmup"), Some(1))
  assert_true(cases[1].groups[0].scale_source == DatasetId)
  // Mixed sources keep the fallback x values apart from recorded scales.
  let plot = scaling_plot(cases[0])
  assert_eq(plot.x_label, "scale (dataset_id where scale is not recorded)")
  assert_true(plot.x_axis is @ir.AxisScale::Categorical)
  assert_true(plot.points.any(point => point.x == "dataset_id 5"))
  assert_true(
    plot.note.contains(
      "Excluded: 1 exploratory observation, 1 warmup observation.",
    ),
  )
}

///|
test "records without phase or scale are confirmatory and keyed by dataset_id" {
  let source =
    #|{"type":"observation","case":"vector-add","implementation":"baseline","dataset_id":0,"elapsed_us":12.5}
    #|{"type":"observation","case":"vector-add","implementation":"baseline","dataset_id":1,"elapsed_us":28.4}
    #|{"type":"observation","case":"vector-add","implementation":"baseline","dataset_id":1,"elapsed_us":30.4}
  guard document_from_jsonl(source) is Ok(document) else {
    abort("expected a document")
  }
  let plot = document.plots[0]
  assert_true(point_texts(plot) == ["baseline@0=12.5", "baseline@1=29.4"])
  assert_eq(plot.x_label, "dataset_id (scale not recorded)")
  assert_true(!plot.note.contains("Excluded"))
  assert_true(
    plot.note.contains("at one dataset_id, pooled over its repetitions."),
  )
}

///|
test "a case with only exploratory observations keeps an empty plot" {
  let source =
    #|{"type":"observation","case":"warm","implementation":"a","dataset_id":0,"scale":"1","phase":"exploratory","elapsed_us":1.0}
    #|{"type":"observation","case":"warm","implementation":"a","dataset_id":0,"scale":"1","phase":"exploratory","elapsed_us":2.0}
  guard document_from_jsonl(source) is Ok(document) else {
    abort("expected a document")
  }
  let plot = document.plots[0]
  assert_true(plot.points.is_empty())
  assert_true(plot.x_axis is @ir.AxisScale::Categorical)
  assert_true(plot.note.contains("Excluded: 2 exploratory observations."))
  assert_true(plot_svg(plot).contains("No observations"))
}

///|
test "each case gets its own scaling plot" {
  let source =
    #|{"type":"observation","case":"add","implementation":"a","dataset_id":0,"scale":"2","phase":"confirmatory","elapsed_us":1.0}
    #|{"type":"observation","case":"mul","implementation":"a","dataset_id":0,"scale":"wide","phase":"confirmatory","elapsed_us":2.0}
  guard document_from_jsonl(source) is Ok(document) else {
    abort("expected a document")
  }
  assert_true(
    document.plots.map(plot => plot.title) ==
    ["Benchmark observations: add", "Benchmark observations: mul"],
  )
}

///|
test "report rejects non-string phase or scale" {
  assert_true(
    document_from_jsonl(
      "{\"type\":\"observation\",\"implementation\":\"a\",\"dataset_id\":0,\"elapsed_us\":1.0,\"phase\":1}",
    )
    is Err("invalid phase at line 1"),
  )
  assert_true(
    document_from_jsonl(
      "{\"type\":\"observation\",\"implementation\":\"a\",\"dataset_id\":0,\"elapsed_us\":1.0,\"scale\":64}",
    )
    is Err("invalid scale at line 1"),
  )
}

///|
test "linear axis layout handles ties, equal values and non-numbers" {
  let linear = (xs : Array[String]) => {
    @ir.Plot::new(
      @ir.PlotKind::Scaling,
      "p",
      "u",
      "median",
      xs.map(x => @ir.PlotPoint::new(x, 1.0, "s")),
      x_axis=@ir.AxisScale::Linear,
    )
  }
  let (values, positions, labelled) = x_layout(linear(["1000", "1", "2"]))
  assert_true(values == ["1", "2", "1000"])
  assert_true(labelled == [true, false, true])
  assert_true(positions[1] < 78.0)
  let (_, positions, _) = x_layout(linear(["5"]))
  assert_true(positions == [478.0])
  let (values, _, _) = x_layout(linear(["5", "five", "1"]))
  assert_true(values == ["5", "five", "1"])
  let (values, _, _) = x_layout(linear(["nan", "1"]))
  assert_true(values == ["nan", "1"])
  let heatmap = @ir.Plot::new(
    @ir.PlotKind::Heatmap,
    "h",
    "u",
    "median",
    [@ir.PlotPoint::new("9", 1.0, "s"), @ir.PlotPoint::new("1", 2.0, "s")],
    x_axis=@ir.AxisScale::Linear,
  )
  let (values, _, _) = x_layout(heatmap)
  assert_true(values == ["9", "1"])
}

///|
test "plot JSON and HTML carry the axis and the caption note" {
  let plot = @ir.Plot::new(
    @ir.PlotKind::Scaling,
    "p",
    "µs/op",
    "median",
    [@ir.PlotPoint::new("1", 1.0, "s"), @ir.PlotPoint::new("2", 2.0, "s")],
    x_axis=@ir.AxisScale::Linear,
    x_label="scale",
    note="Median & more",
  )
  let document = @ir.PlotDocument::new("run", "native", [plot])
  let json = plot_json(document)
  assert_true(json.contains("\"x_axis\":\"linear\""))
  assert_true(json.contains("\"x_label\":\"scale\""))
  assert_true(json.contains("\"note\":\"Median & more\""))
  assert_true(
    plot_json(
      @ir.PlotDocument::new("run", "native", [
        @ir.Plot::new(@ir.PlotKind::Scaling, "p", "u", "raw", []),
      ]),
    ).contains("\"x_axis\":\"categorical\""),
  )
  let page = html(document)
  assert_true(page.contains("<p class=\"note\">Median &amp; more</p>"))
  assert_true(
    plot_svg(plot).contains("scaling plot, median. Median &amp; more"),
  )
}
