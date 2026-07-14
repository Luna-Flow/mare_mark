///|
test "summary JSON includes the full environment snapshot" {
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new("native", "moon-0.1", "-O3", "f64"),
    @model.PerformanceEnvironment::new(
      "runtime",
      "cpu",
      "gc",
      8,
      "monotonic",
      device="gpu",
      frequency_policy="performance",
    ),
    @model.ProvenanceEnvironment::new(
      "os", "host", "timestamp", "revision", "provenance-run",
    ),
  )
  let summary = @model.RunSummary::new(
    "summary-run",
    1,
    2,
    3,
    true,
    None,
    environment~,
  )
  let encoded = summary_json(summary).stringify()
  for
    field in [
      "\"target\":\"native\"", "\"toolchain\":\"moon-0.1\"", "\"compiler_flags\":\"-O3\"",
      "\"dtype_abi\":\"f64\"", "\"runtime\":\"runtime\"", "\"cpu\":\"cpu\"", "\"device\":\"gpu\"",
      "\"concurrency\":8", "\"frequency_policy\":\"performance\"", "\"gc\":\"gc\"",
      "\"clock\":\"monotonic\"", "\"os\":\"os\"", "\"hostname\":\"host\"", "\"timestamp\":\"timestamp\"",
      "\"revision\":\"revision\"", "\"run_id\":\"provenance-run\"",
    ] {
    assert_true(encoded.contains(field))
  }
}
