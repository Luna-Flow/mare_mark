///|
async test "run validates sticky sequence and honors per-iteration setup" {
  let fingerprint_calls = Ref(0)
  let prepare_calls = Ref(0)
  let reset_calls = Ref(0)
  let fixture : @fixture.Fixture[Int32, Int32, Int32] = @fixture.Fixture::new(
    "integers",
    "1",
    context => context.dataset_key.scale,
    (input : Int32) => {
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
  let spec = BenchSpec::advanced(
    "sticky-integers",
    fixture,
    [implementation],
    OutputSink::new(() => 0, (sum, output) => sum + output, sum => sum),
    @experiment.OracleSpec::Reference(oracle),
    [7],
    value => value.to_string(),
    3,
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
    @model.SemanticEnvironment::new(
      @model.ExecutionTarget::Native,
      "test",
      "",
      "int",
    ),
    @model.PerformanceEnvironment::new("test", "test", "none", 1, "mono"),
    @model.ProvenanceEnvironment::new("test", "test", "now", "rev", "run"),
  )
  let memory = @event.InMemorySink::new()
  let plan = spec.compile().unwrap()
  let context = RunContext::new(
    environment,
    memory.as_sink(),
    42,
    validate_protocol(protocol).unwrap(),
  )
  let summary = run(plan, context)
  assert_eq(summary.validation_count, 3)
  assert_eq(summary.passed_count, 3)
  assert_eq(summary.failed_count, 0)
  assert_eq(fingerprint_calls.val, 1)
  assert_eq(prepare_calls.val, 5)
  assert_eq(reset_calls.val, 5)
}

///|
async test "run_batch synchronizes around excluded operation timing" {
  let fixture : @fixture.Fixture[Int32, Int32, Int32] = @fixture.Fixture::new(
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
  let implementation : Implementation[Int32, Int32, Int32] = Implementation::in_process(
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
  let fixture : @fixture.Fixture[Int32, Int32, Int32] = @fixture.Fixture::new(
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
  let implementation : Implementation[Int32, Int32, Int32] = Implementation::in_process(
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
async test "included batch timing surrounds setup and reset" {
  let events : Array[String] = []
  let fixture : @fixture.Fixture[Int32, Int32, Int32] = @fixture.Fixture::new(
    "included-batch",
    "1",
    context => context.dataset_key.scale,
    value => value.to_string(),
    value => value,
    (value, _, _) => {
      events.push("prepare")
      value
    },
    (_, _) => events.push("reset"),
    @model.SetupPolicy::new(
      @model.SetupFrequency::PerBatch,
      @model.SetupTiming::IncludedInMeasurement,
      @model.WorkspaceScope::BatchWorkspace,
    ),
  )
  let implementation : Implementation[Int32, Int32, Int32] = Implementation::in_process(
    "candidate",
    "1",
    () => 0,
    (value, context) => {
      events.push("run")
      @model.OperationResult::completed(value, context)
    },
    synchronize=() => events.push("sync"),
  )
  let result = run_batch(
    fixture,
    1,
    implementation,
    OutputSink::new(() => 0, (sum, value) => sum + value, value => value),
    1,
    0,
    None,
    @bench.Bench(),
  )
  assert_true(result.valid)
  assert_true(events == ["sync", "prepare", "run", "reset", "sync"])
}

///|
async test "calibration scales batch iterations to configured bounds" {
  let fixture : @fixture.Fixture[Int32, Int32, Int32] = @fixture.Fixture::new(
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
  let implementation : Implementation[Int32, Int32, Int32] = Implementation::in_process(
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
async test "run emits a minimized replayable validation failure" {
  let fixture : @fixture.Fixture[Int32, Int32, Int32] = @fixture.Fixture::immutable(
    "shrinking-integers",
    "1",
    context => context.dataset_key.scale,
    value => "fp:" + value.to_string(),
  )
  let implementation = Implementation::stateless("off-by-one", "0.3.0", value => {
    @model.OperationResult::completed(value + 1, ())
  })
  let shrinker = @experiment.Shrinker::new(
    value => if value > 0 { [value / 2] } else { [] },
    value => value.to_string(),
  )
  let spec = BenchSpec::advanced(
    "shrink-failure",
    fixture,
    [implementation],
    OutputSink::keep_last(),
    @experiment.OracleSpec::Reference(
      @experiment.ReferenceOracle::equal("identity", value => value, (
        expected,
        actual,
      ) => expected == actual),
    ),
    [8],
    value => value.to_string(),
    1,
    (value, _) => {
      @model.CaseDescriptor::new("identity", [value.to_string()], "", "")
    },
    value => value.to_string(),
    value => value.to_string(),
    _ => "",
    (value, implementation_id) => {
      @model.ReplaySpec::new(
        "mare-worker",
        [implementation_id, value.to_string()],
        timeout_ms=250,
      )
    },
    shrinker~,
  )
  let memory = @event.InMemorySink::new()
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(
      @model.ExecutionTarget::Native,
      "test",
      "",
      "int",
    ),
    @model.PerformanceEnvironment::new("test", "test", "none", 1, "mono"),
    @model.ProvenanceEnvironment::new("test", "test", "now", "rev", "run"),
  )
  let summary = run(
    spec.compile().unwrap(),
    RunContext::new(
      environment,
      memory.as_sink(),
      42UL,
      ProtocolPreset::QuickCheck.validated(),
    ),
  )
  assert_eq(summary.failed_count, 1)
  assert_eq(memory.failures.length(), 1)
  let failure = memory.failures[0]
  assert_eq(failure.minimal_input, "0")
  assert_true(failure.shrink_path == ["4", "2", "1", "0"])
  guard failure.validation.evidence is Some(evidence) else {
    @test.fail("expected detailed validation evidence")
  }
  assert_eq(evidence.replay.command, "mare-worker")
  assert_true(evidence.replay.arguments == ["off-by-one", "8"])
  assert_eq(evidence.replay.timeout_ms, 250)
}

///|
fn test_environment(run_id : String) -> @model.EnvironmentSnapshot {
  @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(
      @model.ExecutionTarget::Native,
      "test",
      "",
      "int",
    ),
    @model.PerformanceEnvironment::new("test", "test", "none", 1, "mono"),
    @model.ProvenanceEnvironment::new("test", "test", "now", "rev", run_id),
  )
}

///|
async test "relational validation records mismatches and replay evidence" {
  let fixture : @fixture.Fixture[Int32, Int32, Int32] = @fixture.Fixture::immutable(
    "relational",
    "1",
    context => context.dataset_key.scale,
    value => value.to_string(),
  )
  let implementations : Array[Implementation[Int32, Int32, Unit]] = [
    Implementation::stateless("reference", "1", value => {
      @model.OperationResult::completed(value, ())
    }),
    Implementation::stateless("candidate", "1", value => {
      @model.OperationResult::completed(value + 1, ())
    }),
  ]
  let relational = @experiment.RelationalOracle::new("equal-pair", (
    _,
    _,
    _,
    left,
    _,
    right,
  ) => {
    match (left, right) {
      (
        @model.ExecutionOutcome::Value(left_value),
        @model.ExecutionOutcome::Value(right_value),
      ) =>
        if left_value == right_value {
          @model.ValidationStatus::Valid
        } else {
          @model.ValidationStatus::Invalid("pair mismatch")
        }
      _ => @model.ValidationStatus::Invalid("outcome mismatch")
    }
  })
  let spec : BenchSpec[Int32, Int32, Int32, Unit, Int32, Unit, Int32?, Int32?] = BenchSpec::advanced(
    "relational-case",
    fixture,
    implementations,
    OutputSink::keep_last(),
    @experiment.OracleSpec::Relational(relational),
    [5],
    value => value.to_string(),
    1,
    (value, _) => {
      @model.CaseDescriptor::new("identity", [value.to_string()], "", "")
    },
    value => value.to_string(),
    value => value.to_string(),
    _ => "",
    (value, implementation_id) => {
      @model.ReplaySpec::new("worker", [implementation_id, value.to_string()])
    },
  )
  let memory = @event.InMemorySink::new()
  let summary = run(
    spec.compile().unwrap(),
    RunContext::new(
      test_environment("relational"),
      memory.as_sink(),
      3UL,
      minimal_protocol(),
    ),
  )
  assert_eq(summary.validation_count, 1)
  assert_eq(summary.failed_count, 1)
  assert_eq(memory.failures.length(), 1)
  guard memory.failures[0].validation.evidence is Some(evidence) else {
    @test.fail("expected relational evidence")
  }
  assert_eq(evidence.replay.command, "worker")
  assert_true(evidence.replay.arguments == ["candidate", "5"])
}

///|
async test "execution outcomes are counted without becoming validation failures" {
  let fixture : @fixture.Fixture[Int32, Int32, Int32] = @fixture.Fixture::immutable(
    "outcomes",
    "1",
    context => context.dataset_key.scale,
    value => value.to_string(),
  )
  let unsupported : Implementation[Int32, Int32, Unit] = Implementation::stateless(
    "unsupported",
    "1",
    _ => {
      @model.OperationResult::new(
        @model.ExecutionOutcome::Unsupported("not available"),
        None,
      )
    },
  )
  let expected_difference : Implementation[Int32, Int32, Unit] = Implementation::stateless(
    "expected",
    "1",
    _ => {
      @model.OperationResult::new(
        @model.ExecutionOutcome::ExpectedDifference("documented"),
        None,
      )
    },
  )
  let spec = BenchSpec::advanced(
    "outcome-case",
    fixture,
    [unsupported, expected_difference],
    OutputSink::keep_last(),
    @experiment.OracleSpec::Reference(
      @experiment.ReferenceOracle::equal("identity", value => value, (
        expected,
        actual,
      ) => expected == actual),
    ),
    [1],
    value => value.to_string(),
    1,
    (value, _) => {
      @model.CaseDescriptor::new("identity", [value.to_string()], "", "")
    },
    value => value.to_string(),
    value => value.to_string(),
    _ => "",
    (value, implementation_id) => {
      @model.ReplaySpec::new("worker", [implementation_id, value.to_string()])
    },
  )
  let memory = @event.InMemorySink::new()
  let summary = run(
    spec.compile().unwrap(),
    RunContext::new(
      test_environment("outcomes"),
      memory.as_sink(),
      4UL,
      minimal_protocol(),
    ),
  )
  assert_eq(summary.validation_count, 2)
  assert_eq(summary.unsupported_count, 1)
  assert_eq(summary.expected_difference_count, 1)
  assert_eq(summary.failed_count, 0)
  assert_true(memory.failures.is_empty())
}

///|
fn identity_spec() -> BenchSpec[
  Int32,
  Int32,
  Int32,
  Int32,
  Int32,
  Unit,
  Int32?,
  Int32?,
] {
  BenchSpec::advanced(
    "identity-case",
    @fixture.Fixture::immutable(
      "identity",
      "1",
      context => context.dataset_key.scale,
      value => value.to_string(),
    ),
    [
      Implementation::stateless("candidate", "1", value => {
        @model.OperationResult::completed(value, ())
      }),
    ],
    OutputSink::keep_last(),
    @experiment.OracleSpec::Reference(
      @experiment.ReferenceOracle::equal("identity", value => value, (
        expected,
        actual,
      ) => expected == actual),
    ),
    [2],
    value => value.to_string(),
    1,
    (value, _) => {
      @model.CaseDescriptor::new("identity", [value.to_string()], "", "")
    },
    value => value.to_string(),
    value => value.to_string(),
    _ => "",
    (value, implementation_id) => {
      @model.ReplaySpec::new("worker", [implementation_id, value.to_string()])
    },
  )
}

///|
async fn identity_run(
  seed : UInt64,
  provenance_run_id : String,
  timestamp : String,
  sink~ : @event.ObservationSink = @event.InMemorySink::new().as_sink(),
) -> @model.RunSummary {
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(
      @model.ExecutionTarget::Native,
      "test",
      "",
      "int",
    ),
    @model.PerformanceEnvironment::new("test", "test", "none", 1, "mono"),
    @model.ProvenanceEnvironment::new(
      "test", "test", timestamp, "rev", provenance_run_id,
    ),
  )
  run(
    identity_spec().compile().unwrap(),
    RunContext::new(environment, sink, seed, minimal_protocol()),
  )
}

///|
async test "run ids distinguish seeds, provenance run ids and timestamps" {
  let base = identity_run(1UL, "run-a", "2026-10-09T00:00:00Z")
  let protocol = minimal_protocol().protocol
  assert_eq(
    base.run_id,
    @model.run_identity(
      "identity-case",
      protocol,
      1UL,
      @model.ProvenanceEnvironment::new(
        "test", "test", "2026-10-09T00:00:00Z", "rev", "run-a",
      ),
    ),
  )
  assert_true(base.seed is Some(1UL))
  guard base.protocol is Some(recorded) else {
    @test.fail("summary must carry the protocol")
  }
  assert_eq(
    @model.protocol_identity(recorded),
    @model.protocol_identity(protocol),
  )
  let same = identity_run(1UL, "run-a", "2026-10-09T00:00:00Z")
  assert_eq(same.run_id, base.run_id)
  let other_seed = identity_run(2UL, "run-a", "2026-10-09T00:00:00Z")
  let other_run = identity_run(1UL, "run-b", "2026-10-09T00:00:00Z")
  let other_time = identity_run(1UL, "run-a", "2026-10-09T00:00:01Z")
  assert_true(other_seed.run_id != base.run_id)
  assert_true(other_run.run_id != base.run_id)
  assert_true(other_time.run_id != base.run_id)
}

///|
async test "summary JSONL records the protocol used by the run" {
  let jsonl = @event.JsonlSink::new()
  let summary = identity_run(9UL, "run-jsonl", "now", sink=jsonl.as_sink())
  let lines = jsonl.to_jsonl().split("\n").collect()
  let last = @json.parse(lines[lines.length() - 1].to_owned())
  guard last is Object(fields) else { @test.fail("summary must be an object") }
  assert_true(fields.get("type") is Some(String("summary")))
  assert_true(fields.get("run_id") is Some(String(id)) && id == summary.run_id)
  assert_true(fields.get("seed") is Some(String("9")))
  let protocol = minimal_protocol().protocol
  assert_true(
    fields.get("protocol_identity") is Some(String(identity)) &&
    identity == @model.protocol_identity(protocol),
  )
  guard fields.get("protocol") is Some(recorded) else {
    @test.fail("summary must record the protocol")
  }
  assert_eq(
    @model.protocol_canonical_encoding(
      @event.protocol_from_json(recorded).unwrap(),
    ),
    @model.protocol_canonical_encoding(protocol),
  )
}
