///|
#cfg(target="native")
async test "subprocess worker captures abort stderr and timeout" {
  let aborting : Implementation[Int32, Int32, Int32] = Implementation::worker(
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
  let hanging : Implementation[Int32, Int32, Int32] = Implementation::worker(
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
  let implementations : Array[Implementation[Int32, Int32, Unit]] = [
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
  let scales : Array[Int32] = []
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
  let scales : Array[Int32] = []
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
test "protocol validation rejects non-finite durations and thresholds" {
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  let raw = @model.RunProtocol::new(
    @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
    1,
    Some(nan),
    @model.CalibrationProtocol::new(
      nan,
      1,
      10,
      inf,
      @model.BatchPolicy::PerImplementation,
    ),
    nan,
    @model.OrderPolicy::FixedOrder,
    @model.OutlierPolicy::ReportOnly,
    @model.ValidationCoverage::ConfirmatoryOnly,
    0,
    3,
  )
  guard validate_protocol(raw) is Err(errors) else {
    @test.fail("expected protocol errors")
  }
  @test.assert_eq(errors.length(), 4)
  assert_true(errors[0] is InvalidDuration("warmup_time_us", _))
  assert_true(errors[1] is InvalidDuration("target_batch_time_us", _))
  assert_true(errors[2] is InvalidDuration("max_sample_time_us", _))
  assert_true(errors[3] is InvalidPracticalDelta(_))
  let infinite_threshold = @model.RunProtocol::new(
    @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
    1,
    None,
    @model.CalibrationProtocol::new(
      1000.0,
      1,
      10,
      100000.0,
      @model.BatchPolicy::PerImplementation,
    ),
    inf,
    @model.OrderPolicy::FixedOrder,
    @model.OutlierPolicy::ReportOnly,
    @model.ValidationCoverage::ConfirmatoryOnly,
    0,
    3,
  )
  assert_true(
    validate_protocol(infinite_threshold) is Err([InvalidPracticalDelta(_)]),
  )
}

///|
test "protocol JSON round-trips every preset" {
  // `minimal_protocol` covers `FixedOrder`, no warm-up time and
  // `SharedBatchSize`, which no preset uses.
  for
    preset in [
      ProtocolPreset::QuickCheck,
      ProtocolPreset::Development,
      ProtocolPreset::RegressionGate,
      ProtocolPreset::Custom(minimal_protocol()),
    ] {
    let protocol = preset.validated().protocol
    let text = @event.protocol_json(protocol).stringify()
    let decoded = @event.protocol_from_json(@json.parse(text)).unwrap()
    assert_eq(
      @model.protocol_canonical_encoding(decoded),
      @model.protocol_canonical_encoding(protocol),
    )
  }
  let gate = ProtocolPreset::RegressionGate.validated().protocol
  let decoded_gate = @event.protocol_from_json(
    @json.parse(@event.protocol_json(gate).stringify()),
  ).unwrap()
  assert_eq(decoded_gate.repeats_per_dataset, 5)
  assert_true(validate_protocol(decoded_gate) is Ok(_))
  let identities = [
    ProtocolPreset::QuickCheck,
    ProtocolPreset::Development,
    ProtocolPreset::RegressionGate,
  ].map(preset => @model.protocol_identity(preset.validated().protocol))
  assert_true(identities[0] != identities[1])
  assert_true(identities[0] != identities[2])
  assert_true(identities[1] != identities[2])
}
