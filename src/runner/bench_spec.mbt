///|
pub(all) enum BenchConfigError {
  MissingFixture
  MissingOracle
  MissingOutputSink
  MissingSerializer(String)
  EmptyCaseId
  EmptyImplementations
  EmptyScales
  EmptyImplementationId(Int)
  DuplicateImplementationId(String)
  InvalidSequenceLength(Int)
}

///|
pub(all) enum ProtocolConfigError {
  InvalidInteger(String, Int)
  InvalidDuration(String, Double)
  InvalidIterationRange(Int, Int)
  InvalidPracticalDelta(Double)
}

///|
pub struct ValidatedProtocol {
  protocol : @model.RunProtocol
}

///|
pub fn validate_protocol(
  protocol : @model.RunProtocol,
) -> Result[ValidatedProtocol, Array[ProtocolConfigError]] {
  let errors = []
  if protocol.warmup_iterations < 0 {
    errors.push(InvalidInteger("warmup_iterations", protocol.warmup_iterations))
  }
  match protocol.warmup_time_us {
    Some(value) if value < 0.0 =>
      errors.push(InvalidDuration("warmup_time_us", value))
    _ => ()
  }
  if protocol.exploratory_samples < 0 {
    errors.push(
      InvalidInteger("exploratory_samples", protocol.exploratory_samples),
    )
  }
  if protocol.confirmatory_samples <= 0 {
    errors.push(
      InvalidInteger("confirmatory_samples", protocol.confirmatory_samples),
    )
  }
  let calibration = protocol.calibration
  if calibration.target_batch_time_us <= 0.0 {
    errors.push(
      InvalidDuration("target_batch_time_us", calibration.target_batch_time_us),
    )
  }
  if calibration.max_sample_time_us <= 0.0 {
    errors.push(
      InvalidDuration("max_sample_time_us", calibration.max_sample_time_us),
    )
  }
  if calibration.target_batch_time_us > calibration.max_sample_time_us {
    errors.push(
      InvalidDuration("target_batch_time_us", calibration.target_batch_time_us),
    )
  }
  if calibration.min_batch_iterations <= 0 ||
    calibration.max_batch_iterations < calibration.min_batch_iterations {
    errors.push(
      InvalidIterationRange(
        calibration.min_batch_iterations,
        calibration.max_batch_iterations,
      ),
    )
  }
  if protocol.practical_delta_pct < 0.0 {
    errors.push(InvalidPracticalDelta(protocol.practical_delta_pct))
  }
  if errors.is_empty() {
    Ok({ protocol, })
  } else {
    Err(errors)
  }
}

///|
pub(all) enum ProtocolPreset {
  QuickCheck
  Development
  RegressionGate
  Custom(ValidatedProtocol)
}

///|
fn quick_check_protocol() -> @model.RunProtocol {
  @model.RunProtocol::new(
    @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
    1,
    None,
    @model.CalibrationProtocol::new(
      1000.0,
      1,
      1000,
      100000.0,
      @model.BatchPolicy::PerImplementation,
    ),
    1.0,
    @model.OrderPolicy::BalancedBlocks(1),
    @model.OutlierPolicy::ReportOnly,
    @model.ValidationCoverage::ConfirmatoryOnly,
    1,
    3,
  )
}

///|
fn development_protocol() -> @model.RunProtocol {
  @model.RunProtocol::new(
    @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
    3,
    Some(5000.0),
    @model.CalibrationProtocol::new(
      5000.0,
      1,
      10000,
      250000.0,
      @model.BatchPolicy::PerImplementation,
    ),
    1.0,
    @model.OrderPolicy::BalancedBlocks(1),
    @model.OutlierPolicy::ReportOnly,
    @model.ValidationCoverage::EveryDataset,
    3,
    10,
  )
}

///|
fn regression_gate_protocol() -> @model.RunProtocol {
  @model.RunProtocol::new(
    @model.ExperimentDesign::HierarchicalDatasetsAndRepeats,
    10,
    Some(10000.0),
    @model.CalibrationProtocol::new(
      10000.0,
      5,
      10000,
      1000000.0,
      @model.BatchPolicy::PerImplementation,
    ),
    0.5,
    @model.OrderPolicy::BalancedBlocks(1),
    @model.OutlierPolicy::TukeyFence,
    @model.ValidationCoverage::EveryMeasurement,
    5,
    20,
  )
}

///|
pub fn ProtocolPreset::validated(self : ProtocolPreset) -> ValidatedProtocol {
  match self {
    QuickCheck => validate_protocol(quick_check_protocol()).unwrap()
    Development => validate_protocol(development_protocol()).unwrap()
    RegressionGate => validate_protocol(regression_gate_protocol()).unwrap()
    Custom(protocol) => protocol
  }
}

///|
pub struct RunContext {
  seed : UInt64
  environment : @model.EnvironmentSnapshot
  sink : @event.ObservationSink
  protocol : ValidatedProtocol
}

///|
pub fn RunContext::new(
  environment : @model.EnvironmentSnapshot,
  sink : @event.ObservationSink,
  seed : UInt64,
  protocol : ValidatedProtocol,
) -> RunContext {
  { seed, environment, sink, protocol }
}

///|
pub struct BenchSpec[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] {
  case : DifferentialCase[
    Scale,
    Input,
    Prepared,
    Expected,
    Output,
    Context,
    State,
    SinkValue,
  ]
}

///|
pub struct ValidatedBenchPlan[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] {
  case : DifferentialCase[
    Scale,
    Input,
    Prepared,
    Expected,
    Output,
    Context,
    State,
    SinkValue,
  ]
}

///|
pub fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] BenchSpec::advanced(
  id : String,
  fixture : @fixture.Fixture[Scale, Input, Prepared],
  implementations : Array[Implementation[Prepared, Output, Context]],
  output_sink : OutputSink[Output, State, SinkValue],
  oracle : @experiment.OracleSpec[Input, Expected, Output, Context],
  scales : Array[Scale],
  scale_text : (Scale) -> String,
  sequence_length : Int,
  describe : (Input, Int) -> @model.CaseDescriptor,
  input_text : (Input) -> String,
  output_text : (Output) -> String,
  context_text : (Context) -> String,
  replay : (Input, String) -> @model.ReplaySpec,
  shrinker? : @experiment.Shrinker[Input],
) -> BenchSpec[
  Scale,
  Input,
  Prepared,
  Expected,
  Output,
  Context,
  State,
  SinkValue,
] {
  {
    case: differential_case(
      id,
      fixture,
      implementations.copy(),
      output_sink,
      oracle,
      scales.copy(),
      scale_text,
      sequence_length,
      describe,
      input_text,
      output_text,
      context_text,
      replay,
      shrinker?,
    ),
  }
}

///|
pub fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] BenchSpec::compile(
  self : BenchSpec[
    Scale,
    Input,
    Prepared,
    Expected,
    Output,
    Context,
    State,
    SinkValue,
  ],
) -> Result[
  ValidatedBenchPlan[
    Scale,
    Input,
    Prepared,
    Expected,
    Output,
    Context,
    State,
    SinkValue,
  ],
  Array[BenchConfigError],
] {
  let errors = []
  if self.case.id.is_empty() {
    errors.push(EmptyCaseId)
  }
  if self.case.scales.is_empty() {
    errors.push(EmptyScales)
  }
  if self.case.implementations.is_empty() {
    errors.push(EmptyImplementations)
  }
  if self.case.sequence_length <= 0 {
    errors.push(InvalidSequenceLength(self.case.sequence_length))
  }
  let ids : Map[String, Bool] = {}
  for index, implementation in self.case.implementations {
    if implementation.id.is_empty() {
      errors.push(EmptyImplementationId(index))
    } else if ids.contains(implementation.id) {
      errors.push(DuplicateImplementationId(implementation.id))
    } else {
      ids[implementation.id] = true
    }
  }
  if errors.is_empty() {
    Ok({ case: self.case })
  } else {
    Err(errors)
  }
}

///|
pub fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] BenchSpec::with_sequence_length(
  self : BenchSpec[
    Scale,
    Input,
    Prepared,
    Expected,
    Output,
    Context,
    State,
    SinkValue,
  ],
  sequence_length : Int,
) -> BenchSpec[
  Scale,
  Input,
  Prepared,
  Expected,
  Output,
  Context,
  State,
  SinkValue,
] {
  { case: { ..self.case, sequence_length, } }
}

///|
pub(all) enum Case {
  Case
}

///|
pub struct SingleStepCase[Scale] {
  id : String
  scales : Array[Scale]
}

///|
pub struct ImmutableSingleStepCase[Scale, Input] {
  id : String
  scales : Array[Scale]
  fixture : @fixture.Fixture[Scale, Input, Input]
}

///|
pub struct ComparedSingleStepCase[Scale, Input, Output] {
  id : String
  scales : Array[Scale]
  fixture : @fixture.Fixture[Scale, Input, Input]
  implementations : Array[Implementation[Input, Output, Unit]]
}

///|
pub fn[Scale] single_step(
  id : String,
  scales : Array[Scale],
) -> SingleStepCase[Scale] {
  { id, scales: scales.copy() }
}

///|
pub fn[Scale] Case::single_step(
  id : String,
  scales : Array[Scale],
) -> SingleStepCase[Scale] {
  single_step(id, scales)
}

///|
pub fn[Scale] SingleStepCase::compile(
  self : SingleStepCase[Scale],
) -> Result[Unit, Array[BenchConfigError]] {
  let errors = [
    BenchConfigError::MissingFixture,
    BenchConfigError::EmptyImplementations,
    BenchConfigError::MissingOracle,
    BenchConfigError::MissingOutputSink,
  ]
  if self.id.is_empty() {
    errors.push(BenchConfigError::EmptyCaseId)
  }
  if self.scales.is_empty() {
    errors.push(BenchConfigError::EmptyScales)
  }
  Err(errors)
}

///|
pub fn[Scale, Input] SingleStepCase::with_immutable_input(
  self : SingleStepCase[Scale],
  generate : (@model.GenerationContext[Scale]) -> Input,
  fingerprint : (Input) -> String,
) -> ImmutableSingleStepCase[Scale, Input] {
  {
    id: self.id,
    scales: self.scales.copy(),
    fixture: @fixture.Fixture::immutable(
      self.id + "-fixture",
      "1",
      generate,
      fingerprint,
    ),
  }
}

///|
pub fn[Scale, Input, Output] ImmutableSingleStepCase::compare(
  self : ImmutableSingleStepCase[Scale, Input],
  implementations : Array[Implementation[Input, Output, Unit]],
) -> ComparedSingleStepCase[Scale, Input, Output] {
  {
    id: self.id,
    scales: self.scales.copy(),
    fixture: self.fixture,
    implementations: implementations.copy(),
  }
}

///|
pub fn[Scale, Input, Expected, Output] ComparedSingleStepCase::against_equal(
  self : ComparedSingleStepCase[Scale, Input, Output],
  reference : (Input) -> Expected,
  comparator : (Expected, Output) -> Bool,
) -> BenchSpec[Scale, Input, Input, Expected, Output, Unit, Output?, Output?] {
  let oracle = @experiment.ReferenceOracle::equal(
    self.id + "-reference",
    reference,
    comparator,
  )
  let case = differential_case(
    self.id,
    self.fixture,
    self.implementations,
    OutputSink::keep_last(),
    @experiment.OracleSpec::Reference(oracle),
    self.scales,
    _ => "<scale>",
    1,
    (_, _) => @model.CaseDescriptor::new(self.id, [], "stateless", "default"),
    _ => "<input>",
    _ => "<output>",
    _ => "unit",
    (_, implementation_id) => @model.ReplaySpec::new("", [implementation_id]),
  )
  { case, }
}

///|
pub fn[Prepared, Output] Implementation::stateless(
  id : String,
  version : String,
  run : (Prepared) -> @model.OperationResult[Output, Unit],
) -> Implementation[Prepared, Output, Unit] {
  Implementation::in_process(id, version, () => (), (prepared, _) => {
    let result = run(prepared)
    @model.OperationResult::new(result.outcome, Some(()))
  })
}

///|
pub fn[Output] OutputSink::keep_last() -> OutputSink[Output, Output?, Output?] {
  OutputSink::new(() => None, (_, output) => Some(output), state => state)
}
