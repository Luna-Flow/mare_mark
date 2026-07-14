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
test "report rejects invalid or empty event streams" {
  assert_true(document_from_jsonl("not-json") is Err(_))
  assert_true(
    document_from_jsonl("{\"type\":\"summary\",\"run_id\":\"empty\"}") is Err(_),
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
