///|
async test "run validates sticky sequence and honors per-iteration setup" {
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
async test "included batch timing surrounds setup and reset" {
  let events : Array[String] = []
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::new(
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

///|
test "bench spec combinators copy mutable input collections" {
  let scales = [1]
  let implementations = [
    Implementation::stateless("candidate", "1", value => {
      @model.OperationResult::completed(value, ())
    }),
  ]
  let description = single_step("identity", scales)
    .with_immutable_input(context => context.dataset_key.scale, value => {
      value.to_string()
    })
    .compare(implementations)
    .against_equal(value => value, (expected, actual) => expected == actual)
  scales.push(2)
  implementations.push(
    Implementation::stateless("other", "1", value => {
      @model.OperationResult::completed(value, ())
    }),
  )
  let plan = description.compile().unwrap()
  assert_eq(plan.case.scales.length(), 1)
  assert_eq(plan.case.implementations.length(), 1)
  guard description.with_sequence_length(0).compile() is Err(errors) else {
    @test.fail("expected invalid sequence length")
  }
  assert_true(errors[0] is BenchConfigError::InvalidSequenceLength(0))
}

///|
test "compile aggregates benchmark configuration errors" {
  let implementations : Array[Implementation[Int, Int, Unit]] = [
    Implementation::stateless("", "1", value => {
      @model.OperationResult::completed(value, ())
    }),
    Implementation::stateless("duplicate", "1", value => {
      @model.OperationResult::completed(value, ())
    }),
    Implementation::stateless("duplicate", "2", value => {
      @model.OperationResult::completed(value, ())
    }),
  ]
  let scales : Array[Int] = []
  let result = single_step("", scales)
    .with_immutable_input(context => context.dataset_key.scale, value => {
      value.to_string()
    })
    .compare(implementations)
    .against_equal(value => value, (expected, actual) => expected == actual)
    .compile()
  guard result is Err(errors) else { @test.fail("expected compile errors") }
  assert_eq(errors.length(), 4)
  assert_true(errors[0] is BenchConfigError::EmptyCaseId)
  assert_true(errors[1] is BenchConfigError::EmptyScales)
  assert_true(errors[2] is BenchConfigError::EmptyImplementationId(0))
  assert_true(
    errors[3] is BenchConfigError::DuplicateImplementationId("duplicate"),
  )
}

///|
test "incomplete description reports all missing components" {
  let scales : Array[Int] = []
  guard single_step("", scales).compile() is Err(errors) else {
    @test.fail("expected missing component errors")
  }
  assert_eq(errors.length(), 6)
  assert_true(errors[0] is BenchConfigError::MissingFixture)
  assert_true(errors[1] is BenchConfigError::EmptyImplementations)
  assert_true(errors[2] is BenchConfigError::MissingOracle)
  assert_true(errors[3] is BenchConfigError::MissingOutputSink)
  assert_true(errors[4] is BenchConfigError::EmptyCaseId)
  assert_true(errors[5] is BenchConfigError::EmptyScales)
}

///|
test "protocol validation aggregates invalid boundaries" {
  let raw = @model.RunProtocol::new(
    @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
    -1,
    Some(-1.0),
    @model.CalibrationProtocol::new(
      20.0,
      0,
      -1,
      10.0,
      @model.BatchPolicy::PerImplementation,
    ),
    -0.5,
    @model.OrderPolicy::FixedOrder,
    @model.OutlierPolicy::ReportOnly,
    @model.ValidationCoverage::ConfirmatoryOnly,
    -1,
    0,
  )
  guard validate_protocol(raw) is Err(errors) else {
    @test.fail("expected protocol errors")
  }
  assert_true(errors.length() >= 7)
  ignore(ProtocolPreset::QuickCheck.validated())
  ignore(ProtocolPreset::Development.validated())
  ignore(ProtocolPreset::RegressionGate.validated())
}

///|
async test "run emits a minimized replayable validation failure" {
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::immutable(
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
fn minimal_protocol() -> ValidatedProtocol {
  validate_protocol(
    @model.RunProtocol::new(
      @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
      0,
      None,
      @model.CalibrationProtocol::new(
        1.0,
        1,
        1,
        10.0,
        @model.BatchPolicy::SharedBatchSize,
      ),
      1.0,
      @model.OrderPolicy::FixedOrder,
      @model.OutlierPolicy::ReportOnly,
      @model.ValidationCoverage::EveryDataset,
      0,
      1,
    ),
  ).unwrap()
}

///|
async test "relational validation records mismatches and replay evidence" {
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::immutable(
    "relational",
    "1",
    context => context.dataset_key.scale,
    value => value.to_string(),
  )
  let implementations : Array[Implementation[Int, Int, Unit]] = [
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
  let spec : BenchSpec[Int, Int, Int, Unit, Int, Unit, Int?, Int?] = BenchSpec::advanced(
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
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::immutable(
    "outcomes",
    "1",
    context => context.dataset_key.scale,
    value => value.to_string(),
  )
  let unsupported : Implementation[Int, Int, Unit] = Implementation::stateless(
    "unsupported",
    "1",
    _ => {
      @model.OperationResult::new(
        @model.ExecutionOutcome::Unsupported("not available"),
        None,
      )
    },
  )
  let expected_difference : Implementation[Int, Int, Unit] = Implementation::stateless(
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
