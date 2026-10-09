///|
test "summary JSON includes the full environment snapshot" {
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(
      @model.ExecutionTarget::Native,
      "moon-0.1",
      "-O3",
      "f64",
    ),
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

///|
test "observation ADTs encode stable JSONL strings" {
  let observation = @model.Observation::new(
    "case",
    "candidate",
    "1",
    0,
    0,
    0,
    @model.ObservationPhase::Exploratory,
    1.0,
    1,
    @model.BatchSinkStatus::Kept,
    @model.SetupTiming::ExcludedFromMeasurement,
    true,
  )
  let encoded = observation_json(observation).stringify()
  assert_true(encoded.contains("\"artifact_version\":\"mmka_1\""))
  assert_true(encoded.contains("\"phase\":\"exploratory\""))
  assert_true(encoded.contains("\"batch_sink\":\"kept\""))
  assert_true(!encoded.contains("\"scale\""))
  let scaled = @model.Observation::new(
    "case",
    "candidate",
    "1",
    0,
    0,
    0,
    @model.ObservationPhase::Confirmatory,
    1.0,
    1,
    @model.BatchSinkStatus::Kept,
    @model.SetupTiming::ExcludedFromMeasurement,
    true,
    scale_text="1024",
  )
  assert_true(
    observation_json(scaled).stringify().contains("\"scale\":\"1024\""),
  )
  assert_eq(@model.ObservationPhase::Confirmatory.text(), "confirmatory")
  assert_eq(@model.ExecutionTarget::WasmGc.text(), "wasm-gc")
  assert_eq(@model.ExecutionTarget::Custom("gpu").text(), "gpu")
}

///|
test "JSONL sink preserves the versioned event contract" {
  let sink = JsonlSink::new()
  let output = sink.as_sink()
  (output.emit_observation)(
    @model.Observation::new(
      "case",
      "candidate",
      "0.3.0",
      1,
      2,
      3,
      @model.ObservationPhase::Confirmatory,
      4.5,
      6,
      @model.BatchSinkStatus::Kept,
      @model.SetupTiming::ExcludedFromMeasurement,
      true,
    ),
  )
  (output.emit_calibration)(
    @model.CalibrationEvent::new("candidate", 1, 6, 4.5, 10.0, 2),
  )
  ignore((output.finish)(@model.RunSummary::new("run", 1, 0, 1, true, None)))
  let lines = sink.to_jsonl().split("\n")
  assert_eq(lines.length(), 3)
  for line in lines {
    let value = @json.parse(line.to_owned())
    guard value is Object(fields) else { abort("event must be an object") }
    assert_true(fields.get("artifact_version") is Some(String("mmka_1")))
    assert_true(fields.get("type") is Some(String(_)))
  }
}

///|
test "tee sends every event and final location to both sinks" {
  let left = JsonlSink::new()
  let right = JsonlSink::new()
  let sink = tee(left.as_sink(), right.as_sink())
  (sink.emit_calibration)(
    @model.CalibrationEvent::new("candidate", 0, 1, 1.0, 1.0, 0),
  )
  let location = (sink.finish)(
    @model.RunSummary::new("tee", 0, 0, 1, true, None),
  )
  assert_eq(location, "jsonl://memory/tee")
  assert_eq(left.to_jsonl(), right.to_jsonl())
}

///|
test "validation status names remain stable across all protocol outcomes" {
  assert_eq(status_name(@model.ValidationStatus::Valid), "valid")
  assert_eq(status_name(@model.ValidationStatus::Invalid("bad")), "invalid")
  assert_eq(status_name(@model.ValidationStatus::Skipped("skip")), "skipped")
  assert_eq(
    status_name(@model.ValidationStatus::ExpectedDifference("known")),
    "expected_difference",
  )
  assert_eq(
    status_name(@model.ValidationStatus::Unsupported("missing")),
    "unsupported",
  )
  assert_eq(
    status_name(@model.ValidationStatus::InfrastructureFailure("crash")),
    "infrastructure_failure",
  )
}

///|
test "streaming JSONL writes every event and preserves location" {
  let lines : Array[String] = []
  let sink = streaming_jsonl(line => lines.push(line), "file://events.jsonl")
  (sink.emit_validation)(
    @model.Validation::new(
      @model.ValidationStatus::Skipped("not selected"),
      "oracle",
      "candidate",
      "1",
    ),
  )
  (sink.emit_calibration)(
    @model.CalibrationEvent::new("candidate", 0, 1, 2.0, 2.0, 0),
  )
  let location = (sink.finish)(
    @model.RunSummary::new("stream", 0, 1, 1, true, None),
  )
  assert_eq(location, "file://events.jsonl")
  assert_eq(lines.length(), 3)
  assert_true(lines[0].contains("\"status\":\"skipped\""))
  assert_true(lines[1].contains("\"type\":\"calibration\""))
  assert_true(lines[2].contains("\"type\":\"summary\""))
}

///|
test "JSONL keeps setup timing and validation reasons" {
  let jsonl = JsonlSink::new()
  let sink = jsonl.as_sink()
  (sink.emit_observation)(
    @model.Observation::new(
      "matmul",
      "naive",
      "1",
      0,
      0,
      0,
      @model.ObservationPhase::Confirmatory,
      12.5,
      1,
      @model.BatchSinkStatus::Kept,
      @model.SetupTiming::IncludedInMeasurement,
      true,
    ),
  )
  (sink.emit_validation)(
    @model.Validation::new(
      @model.ValidationStatus::Invalid("off by one ulp"),
      "ref",
      "naive",
      "n=4096",
    ),
  )
  (sink.emit_validation)(
    @model.Validation::new(
      @model.ValidationStatus::Valid,
      "ref",
      "naive",
      "n=1",
    ),
  )
  let lines = jsonl
    .to_jsonl()
    .split("\n")
    .map(line => line.to_owned())
    .collect()
  assert_eq(lines.length(), 3)
  assert_true(lines[0].contains("\"setup_timing\":\"included_in_measurement\""))
  assert_true(lines[1].contains("\"reason\":\"off by one ulp\""))
  assert_true(!lines[2].contains("\"reason\""))
}

///|
test "JSONL records setup scopes and measurement validations" {
  let jsonl = JsonlSink::new()
  let sink = jsonl.as_sink()
  (sink.emit_observation)(
    @model.Observation::new(
      "matmul",
      "naive",
      "1",
      3,
      1,
      4,
      @model.ObservationPhase::Confirmatory,
      12.5,
      1,
      @model.BatchSinkStatus::Kept,
      @model.SetupTiming::ExcludedFromMeasurement,
      true,
      setup_frequency=@model.SetupFrequency::PerDataset,
      workspace_scope=@model.WorkspaceScope::DatasetWorkspace,
    ),
  )
  (sink.emit_validation)(
    @model.Validation::new(
      @model.ValidationStatus::Valid,
      "ref",
      "naive",
      "n=4",
      measurement=@model.MeasurementKey::new(3, 1, 4),
    ),
  )
  ignore(
    (sink.finish)(
      @model.RunSummary::new(
        "scopes",
        1,
        1,
        0,
        true,
        None,
        measurement_validation_count=1,
      ),
    ),
  )
  let lines = jsonl
    .to_jsonl()
    .split("\n")
    .map(line => line.to_owned())
    .collect()
  assert_eq(lines.length(), 3)
  assert_true(lines[0].contains("\"setup_frequency\":\"per_dataset\""))
  assert_true(lines[0].contains("\"workspace_scope\":\"dataset_workspace\""))
  assert_true(lines[1].contains("\"validation_scope\":\"measurement\""))
  assert_true(lines[1].contains("\"dataset_id\":3"))
  assert_true(lines[1].contains("\"repetition_id\":1"))
  assert_true(lines[1].contains("\"block_id\":4"))
  assert_true(lines[2].contains("\"measurement_validation_count\":1"))
}

///|
test "setup scope names cover every variant" {
  let frequencies = [
    @model.SetupFrequency::PerRun,
    @model.SetupFrequency::PerDataset,
    @model.SetupFrequency::PerImplementation,
    @model.SetupFrequency::PerSample,
    @model.SetupFrequency::PerBatch,
    @model.SetupFrequency::PerIteration,
  ]
  assert_true(
    frequencies.map(setup_frequency_name) ==
    [
      "per_run", "per_dataset", "per_implementation", "per_sample", "per_batch",
      "per_iteration",
    ],
  )
  let scopes = [
    @model.WorkspaceScope::RunWorkspace,
    @model.WorkspaceScope::DatasetWorkspace,
    @model.WorkspaceScope::ImplementationWorkspace,
    @model.WorkspaceScope::SampleWorkspace,
    @model.WorkspaceScope::BatchWorkspace,
    @model.WorkspaceScope::OperationWorkspace,
  ]
  assert_true(
    scopes.map(workspace_scope_name) ==
    [
      "run_workspace", "dataset_workspace", "implementation_workspace", "sample_workspace",
      "batch_workspace", "operation_workspace",
    ],
  )
}
