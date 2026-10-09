///|
fn protocol_with(
  design : @model.ExperimentDesign,
  coverage : @model.ValidationCoverage,
  exploratory : Int,
  confirmatory : Int,
  warmup? : Int = 1,
  repeats? : Int = 1,
) -> @model.RunProtocol {
  @model.RunProtocol::new(
    design,
    warmup,
    None,
    @model.CalibrationProtocol::new(
      1.0,
      2,
      2,
      10.0,
      @model.BatchPolicy::PerImplementation,
    ),
    1.0,
    @model.OrderPolicy::BalancedBlocks(3),
    @model.OutlierPolicy::ReportOnly,
    coverage,
    exploratory,
    confirmatory,
    repeats_per_dataset=repeats,
  )
}

///|
/// A traced two-implementation case whose fixture, implementations and sink
/// record every call in `trace`, so a run can be compared event by event.
fn traced_spec(
  trace : Array[String],
  frequency : @model.SetupFrequency,
  scales : Array[Int],
) -> BenchSpec[Int, Int, Int, Int, Int, Int, Int, Int] {
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::new(
    "traced",
    "1",
    context => {
      trace.push(
        "materialize scale=\{context.dataset_key.scale} dataset=\{context.dataset_key.dataset_id} seed=\{context.seed}",
      )
      context.dataset_key.scale * 100 + context.dataset_key.dataset_id
    },
    input => "fp:" + input.to_string(),
    input => input,
    (input, implementation_id, sample) => {
      trace.push(
        "prepare input=\{input} impl=\{implementation_id} sample=\{sample.sample_id}",
      )
      input
    },
    (prepared, reset) => {
      trace.push(
        "reset prepared=\{prepared} impl=\{reset.implementation_id} sample=\{reset.sample_id}",
      )
    },
    @model.SetupPolicy::new(
      frequency,
      @model.SetupTiming::ExcludedFromMeasurement,
      @model.WorkspaceScope::DatasetWorkspace,
    ),
  )
  let implementation = (id : String) => {
    Implementation::in_process(id, "1", () => 0, (prepared, context) => {
      @model.OperationResult::completed(prepared + context, context + 1)
    })
  }
  let oracle = @experiment.ReferenceOracle::new(
    "traced-reference",
    () => 0,
    _ => 2,
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
  BenchSpec::advanced(
    "traced-case",
    fixture,
    [implementation("left"), implementation("right")],
    OutputSink::new(() => 0, (sum, output) => sum + output, sum => sum),
    @experiment.OracleSpec::Reference(oracle),
    scales,
    value => value.to_string(),
    2,
    (_, step) => @model.CaseDescriptor::new("add", [step.to_string()], "", ""),
    value => value.to_string(),
    value => value.to_string(),
    value => value.to_string(),
    (input, implementation_id) => {
      @model.ReplaySpec::new("echo", [implementation_id, input.to_string()])
    },
  )
}

///|
fn traced_sink(trace : Array[String]) -> @event.ObservationSink {
  @event.ObservationSink::new(
    observation => {
      trace.push(
        "observation impl=\{observation.implementation_id} dataset=\{observation.dataset_id} repetition=\{observation.repetition_id} block=\{observation.block_id} phase=\{observation.phase.text()} iterations=\{observation.iterations} valid=\{observation.valid}",
      )
    },
    validation => {
      let (dataset, step) = match validation.evidence {
        Some(evidence) => (evidence.dataset_id, evidence.step_id)
        None => (-1, -1)
      }
      let scope = match validation.measurement {
        Some(measurement) =>
          " measurement block=\{measurement.block_id} repetition=\{measurement.repetition_id}"
        None => ""
      }
      trace.push(
        "validation impl=\{validation.implementation_id} dataset=\{dataset} step=\{step}\{scope}",
      )
    },
    calibration => {
      trace.push(
        "calibration impl=\{calibration.implementation_id} dataset=\{calibration.dataset_id} iterations=\{calibration.batch_iterations}",
      )
    },
    summary => {
      trace.push(
        "summary observations=\{summary.observation_count} validations=\{summary.validation_count} calibrations=\{summary.calibration_count}",
      )
      "trace://" + summary.run_id
    },
  )
}

///|
async test "reference oracle sequence length controls both sequences" {
  let spec = traced_spec([], @model.SetupFrequency::PerDataset, [1])
  let sequence_length_calls = Ref(0)
  let reference : @experiment.ReferenceOracle[Int, Int, Int, Int] = @experiment.ReferenceOracle::new(
    "dynamic-length-reference",
    () => 0,
    _ => {
      sequence_length_calls.val += 1
      2
    },
    (input, _, context) => {
      @model.OperationResult::completed(input + context, context + 1)
    },
    (_, _, expected, actual) => {
      match (expected, actual) {
        (
          @model.ExecutionOutcome::Value(expected),
          @model.ExecutionOutcome::Value(actual),
        ) =>
          if expected == actual {
            @model.ValidationStatus::Valid
          } else {
            @model.ValidationStatus::Invalid("value mismatch")
          }
        _ => @model.ValidationStatus::Invalid("outcome mismatch")
      }
    },
    value => value.to_string(),
  )
  let spec : BenchSpec[Int, Int, Int, Int, Int, Int, Int, Int] = {
    case: {
      ..spec.case,
      sequence_length: 2,
      oracle: @experiment.OracleSpec::Reference(reference),
    },
  }
  let validations : Array[@model.ValidationStatus] = []
  let sink = @event.ObservationSink::new(
    _ => (),
    validation => validations.push(validation.status),
    _ => (),
    _ => "trace://dynamic-length",
  )
  ignore(
    run(
      spec.compile().unwrap(),
      RunContext::new(
        test_environment("dynamic-length"),
        sink,
        11UL,
        validate_protocol(
          protocol_with(
            @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
            @model.ValidationCoverage::EveryDataset,
            0,
            1,
            warmup=0,
          ),
        ).unwrap(),
      ),
    ),
  )
  assert_eq(validations.length(), 4)
  assert_eq(sequence_length_calls.val, 1)
  assert_true(
    validations.all(status => status is @model.ValidationStatus::Valid),
  )
}

///|
async test "reference oracle and actual sequence length mismatch fails validation" {
  let spec = traced_spec([], @model.SetupFrequency::PerDataset, [1])
  let reference = @experiment.ReferenceOracle::new(
    "length-mismatch-reference",
    () => 0,
    _ => 3,
    (input, _, context) => {
      @model.OperationResult::completed(input + context, context + 1)
    },
    (_, _, _, _) => @model.ValidationStatus::Valid,
    value => value.to_string(),
  )
  let implementation = Implementation::in_process(
    "short-candidate",
    "1",
    () => 0,
    (prepared, context) => {
      if context >= 1 {
        @model.OperationResult::new(
          @model.ExecutionOutcome::Value(prepared + context),
          None,
        )
      } else {
        @model.OperationResult::completed(prepared + context, context + 1)
      }
    },
  )
  let spec : BenchSpec[Int, Int, Int, Int, Int, Int, Int, Int] = {
    case: {
      ..spec.case,
      sequence_length: 3,
      implementations: [implementation],
      oracle: @experiment.OracleSpec::Reference(reference),
    },
  }
  let validations : Array[@model.ValidationStatus] = []
  let sink = @event.ObservationSink::new(
    _ => (),
    validation => validations.push(validation.status),
    _ => (),
    _ => "trace://length-mismatch",
  )
  ignore(
    run(
      spec.compile().unwrap(),
      RunContext::new(
        test_environment("length-mismatch"),
        sink,
        11UL,
        validate_protocol(
          protocol_with(
            @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
            @model.ValidationCoverage::EveryDataset,
            0,
            1,
            warmup=0,
          ),
        ).unwrap(),
      ),
    ),
  )
  assert_eq(validations.length(), 3)
  assert_true(
    validations.any(status => {
      match status {
        @model.ValidationStatus::Invalid(reason) =>
          reason.contains("sequence length mismatch")
        _ => false
      }
    }),
  )
}

///|
async test "matching early termination still fails the configured sequence length" {
  let spec = traced_spec([], @model.SetupFrequency::PerDataset, [1])
  let reference : @experiment.ReferenceOracle[Int, Int, Int, Int] = @experiment.ReferenceOracle::new(
    "matching-early-stop-reference",
    () => 0,
    _ => 3,
    (input, _, _) => {
      @model.OperationResult::new(@model.ExecutionOutcome::Value(input), None)
    },
    (_, _, _, _) => @model.ValidationStatus::Valid,
    value => value.to_string(),
  )
  let implementation = Implementation::in_process(
    "matching-early-stop",
    "1",
    () => 0,
    (prepared, _) => {
      @model.OperationResult::new(
        @model.ExecutionOutcome::Value(prepared),
        None,
      )
    },
  )
  let spec : BenchSpec[Int, Int, Int, Int, Int, Int, Int, Int] = {
    case: {
      ..spec.case,
      sequence_length: 3,
      implementations: [implementation],
      oracle: @experiment.OracleSpec::Reference(reference),
    },
  }
  let validations : Array[@model.ValidationStatus] = []
  let sink = @event.ObservationSink::new(
    _ => (),
    validation => validations.push(validation.status),
    _ => (),
    _ => "trace://matching-early-stop",
  )
  ignore(
    run(
      spec.compile().unwrap(),
      RunContext::new(
        test_environment("matching-early-stop"),
        sink,
        11UL,
        validate_protocol(
          protocol_with(
            @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
            @model.ValidationCoverage::EveryDataset,
            0,
            1,
            warmup=0,
          ),
        ).unwrap(),
      ),
    ),
  )
  assert_eq(validations.length(), 2)
  assert_true(validations[0] is @model.ValidationStatus::Valid)
  assert_true(
    match validations[1] {
      @model.ValidationStatus::Invalid(reason) =>
        reason.contains("configured 3 steps") &&
        reason.contains("oracle produced 1") &&
        reason.contains("implementation produced 1")
      _ => false
    },
  )
}

///|
async test "non-positive reference sequence length is a run configuration error" {
  let spec = traced_spec([], @model.SetupFrequency::PerDataset, [1])
  let reference = @experiment.ReferenceOracle::new(
    "invalid-length-reference",
    () => 0,
    _ => 0,
    (input, _, context) => {
      @model.OperationResult::completed(input + context, context + 1)
    },
    (_, _, _, _) => @model.ValidationStatus::Valid,
    value => value.to_string(),
  )
  let spec : BenchSpec[Int, Int, Int, Int, Int, Int, Int, Int] = {
    case: { ..spec.case, oracle: @experiment.OracleSpec::Reference(reference), },
  }
  let trace = []
  let raised = try {
    ignore(
      run(
        spec.compile().unwrap(),
        RunContext::new(
          test_environment("invalid-oracle-length"),
          traced_sink(trace),
          11UL,
          validate_protocol(
            protocol_with(
              @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
              @model.ValidationCoverage::EveryDataset,
              0,
              1,
              warmup=0,
            ),
          ).unwrap(),
        ),
      ),
    )
    None
  } catch {
    RunConfigError(errors) => Some(errors)
    _ => None
  }
  assert_true(raised is Some([InvalidOracleSequenceLength(0)]))
  let negative_reference : @experiment.ReferenceOracle[Int, Int, Int, Int] = @experiment.ReferenceOracle::new(
    "negative-length-reference",
    () => 0,
    _ => -1,
    (input, _, context) => {
      @model.OperationResult::completed(input + context, context + 1)
    },
    (_, _, _, _) => @model.ValidationStatus::Valid,
    value => value.to_string(),
  )
  assert_true(
    validation_steps(
      1,
      @experiment.OracleSpec::Reference(negative_reference),
      1,
    )
    is Err(InvalidOracleSequenceLength(-1)),
  )
  assert_true(trace.is_empty())
}

///|
async test "case and oracle sequence length mismatch is rejected before operations" {
  let spec = traced_spec([], @model.SetupFrequency::PerDataset, [1])
  let reference = @experiment.ReferenceOracle::new(
    "different-length-reference",
    () => 0,
    _ => 3,
    (input, _, context) => {
      @model.OperationResult::completed(input + context, context + 1)
    },
    (_, _, _, _) => @model.ValidationStatus::Valid,
    value => value.to_string(),
  )
  let spec : BenchSpec[Int, Int, Int, Int, Int, Int, Int, Int] = {
    case: {
      ..spec.case,
      sequence_length: 2,
      oracle: @experiment.OracleSpec::Reference(reference),
    },
  }
  let trace = []
  let raised = try {
    ignore(
      run(
        spec.compile().unwrap(),
        RunContext::new(
          test_environment("length-disagreement"),
          traced_sink(trace),
          11UL,
          validate_protocol(
            protocol_with(
              @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
              @model.ValidationCoverage::EveryDataset,
              0,
              1,
              warmup=0,
            ),
          ).unwrap(),
        ),
      ),
    )
    None
  } catch {
    RunConfigError(errors) => Some(errors)
    _ => None
  }
  assert_true(raised is Some([OracleSequenceLengthMismatch(2, 3)]))
  assert_true(trace.is_empty())
}

///|
async fn traced_run(
  frequency : @model.SetupFrequency,
  scales : Array[Int],
  protocol : @model.RunProtocol,
) -> (Array[String], @model.RunSummary) {
  let trace = []
  let summary = run(
    traced_spec(trace, frequency, scales).compile().unwrap(),
    RunContext::new(
      test_environment("traced"),
      traced_sink(trace),
      11UL,
      validate_protocol(protocol).unwrap(),
    ),
  )
  (trace, summary)
}

///|
async test "fixed design keeps its dataset and event sequence" {
  let (trace, _) = traced_run(
    @model.SetupFrequency::PerDataset,
    [1, 2],
    protocol_with(
      @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
      @model.ValidationCoverage::EveryDataset,
      1,
      2,
    ),
  )
  inspect(
    trace.join("\n"),
    content=(
      #|materialize scale=1 dataset=0 seed=11
      #|prepare input=100 impl=left sample=-1
      #|reset prepared=100 impl=left sample=-1
      #|prepare input=100 impl=right sample=-1
      #|reset prepared=100 impl=right sample=-1
      #|validation impl=left dataset=0 step=0
      #|validation impl=left dataset=0 step=1
      #|validation impl=right dataset=0 step=0
      #|validation impl=right dataset=0 step=1
      #|prepare input=100 impl=left sample=-1000
      #|reset prepared=100 impl=left sample=-3
      #|reset prepared=100 impl=left sample=-2
      #|calibration impl=left dataset=0 iterations=2
      #|prepare input=100 impl=right sample=-1000
      #|reset prepared=100 impl=right sample=-3
      #|reset prepared=100 impl=right sample=-2
      #|calibration impl=right dataset=0 iterations=2
      #|observation impl=left dataset=0 repetition=0 block=0 phase=exploratory iterations=2 valid=true
      #|observation impl=right dataset=0 repetition=0 block=0 phase=exploratory iterations=2 valid=true
      #|observation impl=right dataset=0 repetition=0 block=1 phase=confirmatory iterations=2 valid=true
      #|observation impl=left dataset=0 repetition=0 block=1 phase=confirmatory iterations=2 valid=true
      #|observation impl=left dataset=0 repetition=1 block=2 phase=confirmatory iterations=2 valid=true
      #|observation impl=right dataset=0 repetition=1 block=2 phase=confirmatory iterations=2 valid=true
      #|reset prepared=100 impl=left sample=2
      #|reset prepared=100 impl=right sample=2
      #|materialize scale=2 dataset=1 seed=11
      #|prepare input=201 impl=left sample=-1
      #|reset prepared=201 impl=left sample=-1
      #|prepare input=201 impl=right sample=-1
      #|reset prepared=201 impl=right sample=-1
      #|validation impl=left dataset=1 step=0
      #|validation impl=left dataset=1 step=1
      #|validation impl=right dataset=1 step=0
      #|validation impl=right dataset=1 step=1
      #|prepare input=201 impl=left sample=-1000
      #|reset prepared=201 impl=left sample=-3
      #|reset prepared=201 impl=left sample=-2
      #|calibration impl=left dataset=1 iterations=2
      #|prepare input=201 impl=right sample=-1000
      #|reset prepared=201 impl=right sample=-3
      #|reset prepared=201 impl=right sample=-2
      #|calibration impl=right dataset=1 iterations=2
      #|observation impl=left dataset=1 repetition=0 block=0 phase=exploratory iterations=2 valid=true
      #|observation impl=right dataset=1 repetition=0 block=0 phase=exploratory iterations=2 valid=true
      #|observation impl=right dataset=1 repetition=0 block=1 phase=confirmatory iterations=2 valid=true
      #|observation impl=left dataset=1 repetition=0 block=1 phase=confirmatory iterations=2 valid=true
      #|observation impl=left dataset=1 repetition=1 block=2 phase=confirmatory iterations=2 valid=true
      #|observation impl=right dataset=1 repetition=1 block=2 phase=confirmatory iterations=2 valid=true
      #|reset prepared=201 impl=left sample=2
      #|reset prepared=201 impl=right sample=2
      #|summary observations=12 validations=8 calibrations=4
    ),
  )
}

///|
async test "fixed design keeps its per-batch setup sequence" {
  let (trace, _) = traced_run(
    @model.SetupFrequency::PerBatch,
    [3],
    protocol_with(
      @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
      @model.ValidationCoverage::ConfirmatoryOnly,
      1,
      1,
      warmup=0,
    ),
  )
  inspect(
    trace.join("\n"),
    content=(
      #|materialize scale=3 dataset=0 seed=11
      #|prepare input=300 impl=left sample=-1
      #|reset prepared=300 impl=left sample=-1
      #|prepare input=300 impl=right sample=-1
      #|reset prepared=300 impl=right sample=-1
      #|validation impl=left dataset=0 step=0
      #|validation impl=left dataset=0 step=1
      #|validation impl=right dataset=0 step=0
      #|validation impl=right dataset=0 step=1
      #|prepare input=300 impl=left sample=-2
      #|reset prepared=300 impl=left sample=-2
      #|calibration impl=left dataset=0 iterations=2
      #|prepare input=300 impl=right sample=-2
      #|reset prepared=300 impl=right sample=-2
      #|calibration impl=right dataset=0 iterations=2
      #|prepare input=300 impl=left sample=-100000
      #|reset prepared=300 impl=left sample=-100000
      #|observation impl=left dataset=0 repetition=0 block=0 phase=exploratory iterations=2 valid=true
      #|prepare input=300 impl=right sample=-100000
      #|reset prepared=300 impl=right sample=-100000
      #|observation impl=right dataset=0 repetition=0 block=0 phase=exploratory iterations=2 valid=true
      #|prepare input=300 impl=right sample=0
      #|reset prepared=300 impl=right sample=0
      #|observation impl=right dataset=0 repetition=0 block=1 phase=confirmatory iterations=2 valid=true
      #|prepare input=300 impl=left sample=0
      #|reset prepared=300 impl=left sample=0
      #|observation impl=left dataset=0 repetition=0 block=1 phase=confirmatory iterations=2 valid=true
      #|summary observations=4 validations=4 calibrations=2
    ),
  )
}

///|
fn block_datasets(trace : Array[String]) -> Array[String] {
  trace
  .filter(line => line.has_prefix("observation"))
  .map(line => {
    let fields = line.split(" ").map(field => field.to_owned()).collect()
    fields[1] + " " + fields[4] + " " + fields[2]
  })
}

///|
async test "multiple datasets design measures a fresh dataset in every block" {
  let (trace, summary) = traced_run(
    @model.SetupFrequency::PerDataset,
    [1, 2],
    protocol_with(
      @model.ExperimentDesign::MultipleDatasetsSingleMeasurement,
      @model.ValidationCoverage::EveryDataset,
      1,
      2,
    ),
  )
  assert_true(
    trace.filter(line => line.has_prefix("materialize")) ==
    [
      "materialize scale=1 dataset=0 seed=11", "materialize scale=1 dataset=1 seed=11",
      "materialize scale=1 dataset=2 seed=11", "materialize scale=2 dataset=3 seed=11",
      "materialize scale=2 dataset=4 seed=11", "materialize scale=2 dataset=5 seed=11",
    ],
  )
  assert_true(
    block_datasets(trace) ==
    [
      "impl=left block=0 dataset=0", "impl=right block=0 dataset=0", "impl=right block=1 dataset=1",
      "impl=left block=1 dataset=1", "impl=left block=2 dataset=2", "impl=right block=2 dataset=2",
      "impl=left block=0 dataset=3", "impl=right block=0 dataset=3", "impl=right block=1 dataset=4",
      "impl=left block=1 dataset=4", "impl=left block=2 dataset=5", "impl=right block=2 dataset=5",
    ],
  )
  // Every dataset is validated (2 implementations x 2 steps); calibration
  // runs once per scale, on the scale's first dataset.
  assert_eq(summary.validation_count, 24)
  assert_eq(summary.measurement_validation_count, 0)
  assert_true(
    trace.filter(line => line.has_prefix("calibration")) ==
    [
      "calibration impl=left dataset=0 iterations=2", "calibration impl=right dataset=0 iterations=2",
      "calibration impl=left dataset=3 iterations=2", "calibration impl=right dataset=3 iterations=2",
    ],
  )
}

///|
async test "hierarchical design repeats each dataset for consecutive blocks" {
  let (trace, summary) = traced_run(
    @model.SetupFrequency::PerDataset,
    [1],
    protocol_with(
      @model.ExperimentDesign::HierarchicalDatasetsAndRepeats,
      @model.ValidationCoverage::EveryDataset,
      2,
      2,
      repeats=2,
    ),
  )
  inspect(
    trace.join("\n"),
    content=(
      #|materialize scale=1 dataset=0 seed=11
      #|prepare input=100 impl=left sample=-1
      #|reset prepared=100 impl=left sample=-1
      #|prepare input=100 impl=right sample=-1
      #|reset prepared=100 impl=right sample=-1
      #|validation impl=left dataset=0 step=0
      #|validation impl=left dataset=0 step=1
      #|validation impl=right dataset=0 step=0
      #|validation impl=right dataset=0 step=1
      #|prepare input=100 impl=left sample=-1000
      #|reset prepared=100 impl=left sample=-3
      #|reset prepared=100 impl=left sample=-2
      #|calibration impl=left dataset=0 iterations=2
      #|prepare input=100 impl=right sample=-1000
      #|reset prepared=100 impl=right sample=-3
      #|reset prepared=100 impl=right sample=-2
      #|calibration impl=right dataset=0 iterations=2
      #|observation impl=left dataset=0 repetition=0 block=0 phase=exploratory iterations=2 valid=true
      #|observation impl=right dataset=0 repetition=0 block=0 phase=exploratory iterations=2 valid=true
      #|observation impl=right dataset=0 repetition=1 block=1 phase=exploratory iterations=2 valid=true
      #|observation impl=left dataset=0 repetition=1 block=1 phase=exploratory iterations=2 valid=true
      #|reset prepared=100 impl=left sample=2
      #|reset prepared=100 impl=right sample=2
      #|materialize scale=1 dataset=1 seed=11
      #|prepare input=101 impl=left sample=-1
      #|reset prepared=101 impl=left sample=-1
      #|prepare input=101 impl=right sample=-1
      #|reset prepared=101 impl=right sample=-1
      #|validation impl=left dataset=1 step=0
      #|validation impl=left dataset=1 step=1
      #|validation impl=right dataset=1 step=0
      #|validation impl=right dataset=1 step=1
      #|prepare input=101 impl=left sample=-4
      #|prepare input=101 impl=right sample=-4
      #|observation impl=left dataset=1 repetition=0 block=2 phase=confirmatory iterations=2 valid=true
      #|observation impl=right dataset=1 repetition=0 block=2 phase=confirmatory iterations=2 valid=true
      #|observation impl=right dataset=1 repetition=1 block=3 phase=confirmatory iterations=2 valid=true
      #|observation impl=left dataset=1 repetition=1 block=3 phase=confirmatory iterations=2 valid=true
      #|reset prepared=101 impl=left sample=2
      #|reset prepared=101 impl=right sample=2
      #|summary observations=8 validations=8 calibrations=2
    ),
  )
  assert_eq(summary.observation_count, 8)
}

///|
async test "hierarchical design numbers datasets uniquely across scales" {
  let (trace, _) = traced_run(
    @model.SetupFrequency::PerSample,
    [1, 2],
    protocol_with(
      @model.ExperimentDesign::HierarchicalDatasetsAndRepeats,
      @model.ValidationCoverage::EveryDataset,
      2,
      4,
      repeats=2,
      warmup=0,
    ),
  )
  let left = block_datasets(trace).filter(line => line.has_prefix("impl=left"))
  assert_true(
    left ==
    [
      "impl=left block=0 dataset=0", "impl=left block=1 dataset=0", "impl=left block=2 dataset=1",
      "impl=left block=3 dataset=1", "impl=left block=4 dataset=2", "impl=left block=5 dataset=2",
      "impl=left block=0 dataset=3", "impl=left block=1 dataset=3", "impl=left block=2 dataset=4",
      "impl=left block=3 dataset=4", "impl=left block=4 dataset=5", "impl=left block=5 dataset=5",
    ],
  )
}

///|
async test "confirmatory-only coverage skips exploratory datasets" {
  let protocol = (coverage : @model.ValidationCoverage) => {
    protocol_with(
      @model.ExperimentDesign::HierarchicalDatasetsAndRepeats,
      coverage,
      2,
      2,
      repeats=2,
    )
  }
  let (every_trace, every) = traced_run(
    @model.SetupFrequency::PerDataset,
    [1],
    protocol(@model.ValidationCoverage::EveryDataset),
  )
  let (confirmatory_trace, confirmatory) = traced_run(
    @model.SetupFrequency::PerDataset,
    [1],
    protocol(@model.ValidationCoverage::ConfirmatoryOnly),
  )
  assert_eq(every.validation_count, 8)
  assert_eq(confirmatory.validation_count, 4)
  let validated = (trace : Array[String]) => {
    trace
    .filter(line => line.has_prefix("validation"))
    .map(line => line.split(" ").collect()[2].to_owned())
  }
  assert_true(
    validated(every_trace) ==
    [
      "dataset=0", "dataset=0", "dataset=0", "dataset=0", "dataset=1", "dataset=1",
      "dataset=1", "dataset=1",
    ],
  )
  assert_true(
    validated(confirmatory_trace) ==
    ["dataset=1", "dataset=1", "dataset=1", "dataset=1"],
  )
  // Under the fixed design the single dataset feeds the confirmatory blocks,
  // so both coverages validate it.
  let (_, fixed_confirmatory) = traced_run(
    @model.SetupFrequency::PerDataset,
    [1],
    protocol_with(
      @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
      @model.ValidationCoverage::ConfirmatoryOnly,
      2,
      2,
    ),
  )
  assert_eq(fixed_confirmatory.validation_count, 4)
}

///|
async test "every-measurement coverage validates before each measured batch" {
  let (trace, summary) = traced_run(
    @model.SetupFrequency::PerDataset,
    [1],
    protocol_with(
      @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
      @model.ValidationCoverage::EveryMeasurement,
      1,
      1,
      warmup=0,
    ),
  )
  inspect(
    trace.join("\n"),
    content=(
      #|materialize scale=1 dataset=0 seed=11
      #|prepare input=100 impl=left sample=-1
      #|reset prepared=100 impl=left sample=-1
      #|prepare input=100 impl=right sample=-1
      #|reset prepared=100 impl=right sample=-1
      #|validation impl=left dataset=0 step=0
      #|validation impl=left dataset=0 step=1
      #|validation impl=right dataset=0 step=0
      #|validation impl=right dataset=0 step=1
      #|prepare input=100 impl=left sample=-2
      #|reset prepared=100 impl=left sample=-2
      #|calibration impl=left dataset=0 iterations=2
      #|prepare input=100 impl=right sample=-2
      #|reset prepared=100 impl=right sample=-2
      #|calibration impl=right dataset=0 iterations=2
      #|reset prepared=100 impl=left sample=-100000
      #|validation impl=left dataset=0 step=0 measurement block=0 repetition=0
      #|validation impl=left dataset=0 step=1 measurement block=0 repetition=0
      #|observation impl=left dataset=0 repetition=0 block=0 phase=exploratory iterations=2 valid=true
      #|reset prepared=100 impl=right sample=-100000
      #|validation impl=right dataset=0 step=0 measurement block=0 repetition=0
      #|validation impl=right dataset=0 step=1 measurement block=0 repetition=0
      #|observation impl=right dataset=0 repetition=0 block=0 phase=exploratory iterations=2 valid=true
      #|reset prepared=100 impl=right sample=0
      #|validation impl=right dataset=0 step=0 measurement block=1 repetition=0
      #|validation impl=right dataset=0 step=1 measurement block=1 repetition=0
      #|observation impl=right dataset=0 repetition=0 block=1 phase=confirmatory iterations=2 valid=true
      #|reset prepared=100 impl=left sample=0
      #|validation impl=left dataset=0 step=0 measurement block=1 repetition=0
      #|validation impl=left dataset=0 step=1 measurement block=1 repetition=0
      #|observation impl=left dataset=0 repetition=0 block=1 phase=confirmatory iterations=2 valid=true
      #|reset prepared=100 impl=left sample=1
      #|reset prepared=100 impl=right sample=1
      #|summary observations=4 validations=12 calibrations=2
    ),
  )
  // 2 dataset validations per implementation plus 2 steps before each of the
  // 4 measured batches.
  assert_eq(summary.validation_count, 12)
  assert_eq(summary.measurement_validation_count, 8)
  assert_eq(summary.passed_count, 12)
}

///|
async test "every-measurement coverage prepares short-lived setup per batch" {
  let (trace, summary) = traced_run(
    @model.SetupFrequency::PerBatch,
    [1],
    protocol_with(
      @model.ExperimentDesign::MultipleDatasetsSingleMeasurement,
      @model.ValidationCoverage::EveryMeasurement,
      0,
      1,
      warmup=0,
    ),
  )
  inspect(
    trace.join("\n"),
    content=(
      #|materialize scale=1 dataset=0 seed=11
      #|prepare input=100 impl=left sample=-1
      #|reset prepared=100 impl=left sample=-1
      #|prepare input=100 impl=right sample=-1
      #|reset prepared=100 impl=right sample=-1
      #|validation impl=left dataset=0 step=0
      #|validation impl=left dataset=0 step=1
      #|validation impl=right dataset=0 step=0
      #|validation impl=right dataset=0 step=1
      #|prepare input=100 impl=left sample=-2
      #|reset prepared=100 impl=left sample=-2
      #|calibration impl=left dataset=0 iterations=2
      #|prepare input=100 impl=right sample=-2
      #|reset prepared=100 impl=right sample=-2
      #|calibration impl=right dataset=0 iterations=2
      #|prepare input=100 impl=left sample=0
      #|reset prepared=100 impl=left sample=0
      #|validation impl=left dataset=0 step=0 measurement block=0 repetition=0
      #|validation impl=left dataset=0 step=1 measurement block=0 repetition=0
      #|prepare input=100 impl=left sample=0
      #|reset prepared=100 impl=left sample=0
      #|observation impl=left dataset=0 repetition=0 block=0 phase=confirmatory iterations=2 valid=true
      #|prepare input=100 impl=right sample=0
      #|reset prepared=100 impl=right sample=0
      #|validation impl=right dataset=0 step=0 measurement block=0 repetition=0
      #|validation impl=right dataset=0 step=1 measurement block=0 repetition=0
      #|prepare input=100 impl=right sample=0
      #|reset prepared=100 impl=right sample=0
      #|observation impl=right dataset=0 repetition=0 block=0 phase=confirmatory iterations=2 valid=true
      #|summary observations=2 validations=8 calibrations=2
    ),
  )
  assert_eq(summary.measurement_validation_count, 4)
}

///|
async test "every-measurement relational validation targets the measured implementation" {
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::immutable(
    "relational-measurement",
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
    if left.value_option() == right.value_option() {
      @model.ValidationStatus::Valid
    } else {
      @model.ValidationStatus::Invalid("pair mismatch")
    }
  })
  let spec : BenchSpec[Int, Int, Int, Unit, Int, Unit, Int?, Int?] = BenchSpec::advanced(
    "relational-measurement",
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
      test_environment("relational-measurement"),
      memory.as_sink(),
      3UL,
      validate_protocol(
        protocol_with(
          @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
          @model.ValidationCoverage::EveryMeasurement,
          0,
          1,
          warmup=0,
        ),
      ).unwrap(),
    ),
  )
  assert_eq(summary.validation_count, 3)
  assert_eq(summary.measurement_validation_count, 2)
  assert_eq(summary.failed_count, 3)
  assert_eq(memory.failures.length(), 3)
  let measured = memory.validations
    .filter(validation => validation.measurement is Some(_))
    .map(validation => validation.implementation_id)
  let observed = memory.observations.map(observation => {
    observation.implementation_id
  })
  assert_true(measured == observed)
  assert_true(memory.validations[0].measurement is None)
}

///|
async test "per-run setup is rejected when a case has several datasets" {
  let trace = []
  let spec = traced_spec(trace, @model.SetupFrequency::PerRun, [1, 2])
  guard spec.compile() is Err(errors) else {
    @test.fail("expected per-run setup to be rejected")
  }
  assert_true(errors is [PerRunSetupWithMultipleDatasets(2)])
  let single = traced_spec(trace, @model.SetupFrequency::PerRun, [1])
  let multiple = validate_protocol(
    protocol_with(
      @model.ExperimentDesign::MultipleDatasetsSingleMeasurement,
      @model.ValidationCoverage::EveryDataset,
      1,
      2,
    ),
  ).unwrap()
  assert_true(single.compile() is Ok(_))
  assert_true(
    single.compile(protocol=multiple)
    is Err([PerRunSetupWithMultipleDatasets(3)]),
  )
  let raised = try {
    ignore(
      run(
        single.compile().unwrap(),
        RunContext::new(
          test_environment("per-run"),
          traced_sink(trace),
          11UL,
          multiple,
        ),
      ),
    )
    None
  } catch {
    RunConfigError(errors) => Some(errors)
    _ => None
  }
  assert_true(raised is Some([PerRunSetupWithMultipleDatasets(3)]))
  assert_true(trace.is_empty())
}

///|
async test "per-run setup with one dataset behaves like per-dataset setup" {
  let protocol = protocol_with(
    @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
    @model.ValidationCoverage::EveryDataset,
    1,
    2,
  )
  let (per_run, _) = traced_run(@model.SetupFrequency::PerRun, [1], protocol)
  let (per_dataset, _) = traced_run(
    @model.SetupFrequency::PerDataset,
    [1],
    protocol,
  )
  assert_true(per_run == per_dataset)
}

///|
async test "observations record setup frequency and workspace scope" {
  let trace = []
  let memory = @event.InMemorySink::new()
  ignore(
    run(
      traced_spec(trace, @model.SetupFrequency::PerImplementation, [1])
      .compile()
      .unwrap(),
      RunContext::new(
        test_environment("setup-fields"),
        memory.as_sink(),
        11UL,
        minimal_protocol(),
      ),
    ),
  )
  assert_true(!memory.observations.is_empty())
  for observation in memory.observations {
    assert_true(
      observation.setup_frequency
      is Some(@model.SetupFrequency::PerImplementation),
    )
    assert_true(
      observation.workspace_scope
      is Some(@model.WorkspaceScope::DatasetWorkspace),
    )
  }
}

///|
test "protocol validation checks repeats per dataset" {
  let hierarchical = (exploratory, confirmatory, repeats) => {
    validate_protocol(
      protocol_with(
        @model.ExperimentDesign::HierarchicalDatasetsAndRepeats,
        @model.ValidationCoverage::EveryDataset,
        exploratory,
        confirmatory,
        repeats~,
      ),
    )
  }
  assert_true(hierarchical(4, 6, 2) is Ok(_))
  assert_true(hierarchical(0, 3, 3) is Ok(_))
  assert_true(
    hierarchical(4, 6, 0) is Err([InvalidInteger("repeats_per_dataset", 0)]),
  )
  assert_true(
    hierarchical(3, 5, 2)
    is Err(
      [
        IndivisibleSamples("exploratory_samples", 3, 2),
        IndivisibleSamples("confirmatory_samples", 5, 2),
      ]
    ),
  )
  for
    design in [
      @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
      @model.ExperimentDesign::MultipleDatasetsSingleMeasurement,
    ] {
    assert_true(
      validate_protocol(
        protocol_with(
          design,
          @model.ValidationCoverage::EveryDataset,
          2,
          2,
          repeats=2,
        ),
      )
      is Err([UnusedRepeatsPerDataset(2)]),
    )
    assert_true(
      validate_protocol(
        protocol_with(design, @model.ValidationCoverage::EveryDataset, 2, 2),
      )
      is Ok(_),
    )
  }
  let gate = ProtocolPreset::RegressionGate.validated().protocol
  assert_true(
    gate.experiment_design
    is @model.ExperimentDesign::HierarchicalDatasetsAndRepeats,
  )
  assert_eq(gate.repeats_per_dataset, 5)
  assert_eq(datasets_per_scale(gate), 5)
  assert_eq(
    datasets_per_scale(ProtocolPreset::QuickCheck.validated().protocol),
    1,
  )
}
