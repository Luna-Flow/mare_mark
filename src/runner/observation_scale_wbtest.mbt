///|
/// One exploratory and two confirmatory samples per dataset, with tiny batches.
fn scale_test_context(sink : @event.ObservationSink) -> RunContext {
  let protocol = validate_protocol(
    @model.RunProtocol::new(
      @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
      0,
      None,
      @model.CalibrationProtocol::new(
        1.0,
        1,
        1,
        10.0,
        @model.BatchPolicy::PerImplementation,
      ),
      1.0,
      @model.OrderPolicy::FixedOrder,
      @model.OutlierPolicy::ReportOnly,
      @model.ValidationCoverage::EveryDataset,
      1,
      2,
    ),
  ).unwrap()
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(
      @model.ExecutionTarget::Native,
      "test",
      "",
      "int",
    ),
    @model.PerformanceEnvironment::new("test", "test", "none", 1, "mono"),
    @model.ProvenanceEnvironment::new("test", "test", "now", "rev", "scale"),
  )
  RunContext::new(environment, sink, 7UL, protocol)
}

///|
fn observation_lines(jsonl : String) -> Array[String] {
  jsonl
  .split("\n")
  .filter(line => line.contains("\"type\":\"observation\""))
  .map(line => line.to_owned())
  .to_array()
}

///|
async test "observation JSONL records the scale of every dataset" {
  let implementation = Implementation::stateless("identity", "1", (value : Int) => {
    @model.OperationResult::completed(value, ())
  })
  let spec = BenchSpec::advanced(
    "scaled-identity",
    @fixture.Fixture::immutable(
      "integers",
      "1",
      context => context.dataset_key.scale,
      (value : Int) => value.to_string(),
    ),
    [implementation],
    OutputSink::keep_last(),
    @experiment.OracleSpec::Reference(
      @experiment.ReferenceOracle::equal("identity", value => value, (
        expected,
        actual,
      ) => expected == actual),
    ),
    [16, 4],
    value => "n=" + value.to_string(),
    1,
    (value, _) => {
      @model.CaseDescriptor::new("identity", [value.to_string()], "", "")
    },
    value => value.to_string(),
    value => value.to_string(),
    _ => "",
    (_, implementation_id) => @model.ReplaySpec::new("", [implementation_id]),
  )
  let record = @event.JsonlSink::new()
  let memory = @event.InMemorySink::new()
  let summary = run(
    spec.compile().unwrap(),
    scale_test_context(@event.tee(record.as_sink(), memory.as_sink())),
  )
  assert_eq(summary.observation_count, 6)
  assert_true(
    memory.observations.map(observation => observation.scale_text) ==
    ["n=16", "n=16", "n=16", "n=4", "n=4", "n=4"],
  )
  let lines = observation_lines(record.to_jsonl())
  assert_eq(lines.length(), 6)
  for index, line in lines {
    let expected = if index < 3 {
      "\"dataset_id\":0,"
    } else {
      "\"dataset_id\":1,"
    }
    let scale = if index < 3 {
      "\"scale\":\"n=16\""
    } else {
      "\"scale\":\"n=4\""
    }
    assert_true(line.contains(expected))
    assert_true(line.contains(scale))
  }
}

///|
async test "single-step builder records no scale text" {
  let implementation = Implementation::stateless("identity", "1", (value : Int) => {
    @model.OperationResult::completed(value, ())
  })
  let plan = single_step("unscaled-identity", [16, 4])
    .with_immutable_input(context => context.dataset_key.scale, value => {
      value.to_string()
    })
    .compare([implementation])
    .against_equal(value => value, (expected, actual) => expected == actual)
    .compile()
    .unwrap()
  let record = @event.JsonlSink::new()
  ignore(run(plan, scale_test_context(record.as_sink())))
  let lines = observation_lines(record.to_jsonl())
  assert_eq(lines.length(), 6)
  assert_true(lines.all(line => !line.contains("\"scale\"")))
}
