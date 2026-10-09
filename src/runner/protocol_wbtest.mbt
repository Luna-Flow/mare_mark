///|
fn protocol_with(
  design : @model.ExperimentDesign,
  coverage : @model.ValidationCoverage,
  exploratory : Int,
  confirmatory : Int,
  warmup? : Int = 1,
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
      trace.push(
        "validation impl=\{validation.implementation_id} dataset=\{dataset} step=\{step}",
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
