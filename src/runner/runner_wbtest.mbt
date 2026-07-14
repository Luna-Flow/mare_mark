///|
async test "run_case validates sticky sequence and honors per-iteration setup" {
  let fingerprint_calls = Ref(0)
  let prepare_calls = Ref(0)
  let reset_calls = Ref(0)
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::new(
    "integers",
    "1",
    context => context.dataset_key.scale,
    (input : Int) => {
      fingerprint_calls.val += 1
      "fp:" + input.to_string()
    },
    input => input,
    (input, _, _) => {
      prepare_calls.val += 1
      input
    },
    (_, _) => reset_calls.val += 1,
    @model.SetupPolicy::new(
      @model.SetupFrequency::PerIteration,
      @model.SetupTiming::ExcludedFromMeasurement,
      @model.WorkspaceScope::OperationWorkspace,
    ),
  )
  let implementation = Implementation::in_process(
    "candidate",
    "1.2.3",
    () => 0,
    (prepared, context) => {
      @model.OperationResult::completed(prepared + context, context + 1)
    },
  )
  let oracle = @experiment.ReferenceOracle::new(
    "integer-reference",
    () => 0,
    _ => 3,
    (input, _, context) => {
      @model.OperationResult::completed(input + context, context + 1)
    },
    (_, _, expected, actual) => {
      match (expected, actual) {
        (
          @model.ExecutionOutcome::Value(left),
          @model.ExecutionOutcome::Value(right),
        ) =>
          if left == right {
            @model.ValidationStatus::Valid
          } else {
            @model.ValidationStatus::Invalid("value mismatch")
          }
        _ => @model.ValidationStatus::Invalid("outcome mismatch")
      }
    },
    value => value.to_string(),
  )
  let case = DifferentialCase::new(
    "sticky-integers",
    fixture,
    [implementation],
    OutputSink::new(() => 0, (sum, output) => sum + output, sum => sum),
    @experiment.OracleSpec::Reference(oracle),
    [7],
    value => value.to_string(),
    _ => 3,
    (_, step) => {
      @model.CaseDescriptor::new(
        "add",
        ["7", step.to_string()],
        "sticky",
        "half_even",
      )
    },
    value => value.to_string(),
    value => value.to_string(),
    value => value.to_string(),
    (input, implementation_id) => {
      @model.ReplaySpec::new("echo", [implementation_id, input.to_string()])
    },
  )
  let protocol = @model.RunProtocol::new(
    @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
    0,
    None,
    @model.CalibrationProtocol::new(
      1.0,
      2,
      2,
      10.0,
      @model.BatchPolicy::PerImplementation,
    ),
    1.0,
    @model.OrderPolicy::FixedOrder,
    @model.OutlierPolicy::ReportOnly,
    @model.ValidationCoverage::EveryDataset,
    0,
    1,
  )
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new("native", "test", "", "int"),
    @model.PerformanceEnvironment::new("test", "test", "none", 1, "mono"),
    @model.ProvenanceEnvironment::new("test", "test", "now", "rev", "run"),
  )
  let memory = @event.InMemorySink::new()
  let summary = run_case(case, protocol, environment, memory.as_sink(), 42)
  assert_eq(summary.validation_count, 3)
  assert_eq(summary.passed_count, 3)
  assert_eq(summary.failed_count, 0)
  assert_eq(fingerprint_calls.val, 1)
  assert_eq(prepare_calls.val, 5)
  assert_eq(reset_calls.val, 5)
}

///|
async test "run_batch synchronizes around excluded operation timing" {
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::new(
    "synchronization",
    "1",
    context => context.dataset_key.scale,
    value => value.to_string(),
    value => value,
    (value, _, _) => value,
    (_, _) => (),
    @model.SetupPolicy::new(
      @model.SetupFrequency::PerIteration,
      @model.SetupTiming::ExcludedFromMeasurement,
      @model.WorkspaceScope::OperationWorkspace,
    ),
  )
  let synchronizations = Ref(0)
  let implementation : Implementation[Int, Int, Int] = Implementation::in_process(
    "candidate",
    "1",
    () => 0,
    (value, context) => @model.OperationResult::completed(value, context),
    synchronize=() => synchronizations.val += 1,
  )
  let result = run_batch(
    fixture,
    1,
    implementation,
    OutputSink::new(() => 0, (sum, value) => sum + value, value => value),
    2,
    0,
    None,
    @bench.Bench(),
  )
  assert_true(result.valid)
  assert_eq(synchronizations.val, 4)
}

///|
async test "excluded batch timing stops before reset" {
  let events : Array[String] = []
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::new(
    "excluded-reset",
    "1",
    context => context.dataset_key.scale,
    value => value.to_string(),
    value => value,
    (value, _, _) => value,
    (_, _) => events.push("reset"),
    @model.SetupPolicy::new(
      @model.SetupFrequency::PerBatch,
      @model.SetupTiming::ExcludedFromMeasurement,
      @model.WorkspaceScope::BatchWorkspace,
    ),
  )
  let implementation : Implementation[Int, Int, Int] = Implementation::in_process(
    "candidate",
    "1",
    () => 0,
    (value, context) => {
      events.push("run")
      @model.OperationResult::completed(value, context)
    },
    synchronize=() => events.push("sync"),
  )
  ignore(
    run_batch(
      fixture,
      1,
      implementation,
      OutputSink::new(() => 0, (sum, value) => sum + value, value => value),
      1,
      0,
      None,
      @bench.Bench(),
    ),
  )
  assert_true(events == ["sync", "run", "sync", "reset"])
}

///|
#cfg(target="native")
async test "subprocess worker captures abort stderr and timeout" {
  let aborting : Implementation[Int, Int, Int] = Implementation::worker(
    "aborting",
    "1",
    () => 0,
    WorkerSpec::new(
      "sh",
      (_, _) => ["-c", "printf 'decimal abort' >&2; exit 7"],
      _ => @model.OperationResult::completed(0, 0),
      timeout_ms=1000,
    ),
  )
  let aborted = execute_operation(aborting, 0, 0)
  match aborted.outcome {
    @model.ExecutionOutcome::Aborted(7, stderr) =>
      assert_true(stderr.contains("decimal abort"))
    _ => @test.fail("expected aborted worker")
  }
  let hanging : Implementation[Int, Int, Int] = Implementation::worker(
    "hanging",
    "1",
    () => 0,
    WorkerSpec::new(
      "sh",
      (_, _) => ["-c", "sleep 1"],
      _ => @model.OperationResult::completed(0, 0),
      timeout_ms=10,
    ),
  )
  let timed_out = execute_operation(hanging, 0, 0)
  assert_true(timed_out.outcome is @model.ExecutionOutcome::Timeout(10, _))
}

///|
async test "calibration scales batch iterations to configured bounds" {
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::new(
    "calibration",
    "1",
    context => context.dataset_key.scale,
    value => value.to_string(),
    value => value,
    (value, _, _) => value,
    (_, _) => (),
    @model.SetupPolicy::new(
      @model.SetupFrequency::PerBatch,
      @model.SetupTiming::ExcludedFromMeasurement,
      @model.WorkspaceScope::BatchWorkspace,
    ),
  )
  let implementation : Implementation[Int, Int, Int] = Implementation::in_process(
    "candidate",
    "1",
    () => 0,
    (value, context) => @model.OperationResult::completed(value, context + 1),
  )
  let protocol = @model.CalibrationProtocol::new(
    1000000000.0,
    2,
    8,
    1000000000.0,
    @model.BatchPolicy::PerImplementation,
  )
  let (_, iterations, retries) = calibrate_batch(
    fixture,
    1,
    implementation,
    OutputSink::new(() => 0, (sum, value) => sum + value, value => value),
    protocol,
    None,
    @bench.Bench(),
  )
  assert_eq(iterations, 8)
  assert_true(retries > 0)
}

///|
test "measurement order honors fixed and seeded balanced policies" {
  assert_true(
    measurement_order(@model.OrderPolicy::FixedOrder, 3, 2, 99) == [0, 1, 2],
  )
  assert_true(
    measurement_order(@model.OrderPolicy::BalancedBlocks(7), 3, 0, 7) ==
    [0, 1, 2],
  )
  let positions = Array::makei(3, _ => Array::makei(3, _ => 0))
  for block_id = 0; block_id < 3; block_id = block_id + 1 {
    let order = measurement_order(
      @model.OrderPolicy::BalancedBlocks(13),
      3,
      block_id,
      99,
    )
    for position = 0; position < order.length(); position = position + 1 {
      positions[order[position]][position] += 1
    }
  }
  assert_true(positions == [[1, 1, 1], [1, 1, 1], [1, 1, 1]])
}
