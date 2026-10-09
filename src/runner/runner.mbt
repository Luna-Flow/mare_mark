///|
pub struct WorkerSpec[Prepared, Output, Context] {
  command : String
  build_arguments : (Prepared, Context) -> Array[String]
  decode : (String) -> @model.OperationResult[Output, Context]
  timeout_ms : Int
  cwd : String?
}

///|
pub fn[Prepared, Output, Context] WorkerSpec::new(
  command : String,
  build_arguments : (Prepared, Context) -> Array[String],
  decode : (String) -> @model.OperationResult[Output, Context],
  timeout_ms? : Int = 5000,
  cwd? : String,
) -> WorkerSpec[Prepared, Output, Context] {
  { command, build_arguments, decode, timeout_ms, cwd, }
}

///|
pub enum ExecutionMode[Prepared, Output, Context] {
  InProcess((Prepared, Context) -> @model.OperationResult[Output, Context])
  Subprocess(WorkerSpec[Prepared, Output, Context])
}

///|
pub struct Implementation[Prepared, Output, Context] {
  id : String
  version : String
  initial_context : () -> Context
  execution : ExecutionMode[Prepared, Output, Context]
  synchronize : () -> Unit
}

///|
pub fn[Prepared, Output, Context] Implementation::in_process(
  id : String,
  version : String,
  initial_context : () -> Context,
  run : (Prepared, Context) -> @model.OperationResult[Output, Context],
  synchronize? : () -> Unit = () => (),
) -> Implementation[Prepared, Output, Context] {
  { id, version, initial_context, execution: InProcess(run), synchronize, }
}

///|
pub fn[Prepared, Output, Context] Implementation::worker(
  id : String,
  version : String,
  initial_context : () -> Context,
  worker : WorkerSpec[Prepared, Output, Context],
  synchronize? : () -> Unit = () => (),
) -> Implementation[Prepared, Output, Context] {
  { id, version, initial_context, execution: Subprocess(worker), synchronize, }
}

///|
pub struct OutputSink[Output, State, SinkValue] {
  initial : () -> State
  fold : (State, Output) -> State
  finish : (State) -> SinkValue
}

///|
pub fn[Output, State, SinkValue] OutputSink::new(
  initial : () -> State,
  fold : (State, Output) -> State,
  finish : (State) -> SinkValue,
) -> OutputSink[Output, State, SinkValue] {
  { initial, fold, finish, }
}

///|
pub struct DifferentialCase[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] {
  id : String
  fixture : @fixture.Fixture[Scale, Input, Prepared]
  implementations : Array[Implementation[Prepared, Output, Context]]
  output_sink : OutputSink[Output, State, SinkValue]
  oracle : @experiment.OracleSpec[Input, Expected, Output, Context]
  scales : Array[Scale]
  scale_text : (Scale) -> String
  sequence_length : Int
  describe : (Input, Int) -> @model.CaseDescriptor
  input_text : (Input) -> String
  output_text : (Output) -> String
  context_text : (Context) -> String
  shrinker : @experiment.Shrinker[Input]?
  replay : (Input, String) -> @model.ReplaySpec
}

///|
fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] differential_case(
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
) -> DifferentialCase[
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
    id,
    fixture,
    implementations,
    output_sink,
    oracle,
    scales,
    scale_text,
    sequence_length,
    describe,
    input_text,
    output_text,
    context_text,
    shrinker,
    replay,
  }
}

///|
pub fn balanced_order(implementation_count : Int, block_id : Int) -> Array[Int] {
  Array::makei(implementation_count, index => {
    (index + block_id) % implementation_count
  })
}

///|
pub async fn[Prepared, Output, Context] execute_operation(
  implementation : Implementation[Prepared, Output, Context],
  prepared : Prepared,
  context : Context,
) -> @model.OperationResult[Output, Context] {
  match implementation.execution {
    InProcess(run) => run(prepared, context)
    Subprocess(worker) => {
      let captured = try
        @async.with_timeout_opt(worker.timeout_ms, () => {
          collect_worker_output(worker, prepared, context)
        })
      catch {
        error =>
          return @model.OperationResult::new(
            @model.ExecutionOutcome::ParseFailure(@debug.to_string(error)),
            None,
          )
      } noraise {
        value => value
      }
      match captured {
        None =>
          @model.OperationResult::new(
            @model.ExecutionOutcome::Timeout(
              worker.timeout_ms,
              "worker exceeded timeout",
            ),
            None,
          )
        Some((exit_code, stdout, stderr)) =>
          if exit_code != 0 {
            @model.OperationResult::new(
              @model.ExecutionOutcome::Aborted(exit_code, stderr),
              None,
              stdout~,
              stderr~,
              exit_code~,
            )
          } else {
            let decoded = (worker.decode)(stdout)
            @model.OperationResult::new(
              decoded.outcome,
              decoded.next_context,
              stdout~,
              stderr~,
              exit_code~,
            )
          }
      }
    }
  }
}

///|
fn[Value] outcome_text(
  outcome : @model.ExecutionOutcome[Value],
  value_text : (Value) -> String,
) -> String {
  match outcome {
    Value(value) | RaisedFlags(value, _) => value_text(value)
    Unsupported(reason) | ParseFailure(reason) | ExpectedDifference(reason) =>
      reason
    Trapped(trap, _) => trap
    Aborted(code, stderr) => "exit " + code.to_string() + ": " + stderr
    Timeout(milliseconds, reason) => milliseconds.to_string() + "ms: " + reason
  }
}

///|
fn[Value] trap_text(outcome : @model.ExecutionOutcome[Value]) -> String {
  match outcome {
    Trapped(trap, _) => trap
    _ => ""
  }
}

///|
async fn[Scale, Input, Prepared, Output, Context] validation_sequence(
  fixture : @fixture.Fixture[Scale, Input, Prepared],
  input : Input,
  implementation : Implementation[Prepared, Output, Context],
  steps : Int,
) -> Array[@model.OperationResult[Output, Context]] {
  let prepared = (fixture.prepare)(
    (fixture.clone_input)(input),
    implementation.id,
    @fixture.SampleContext::new(-1, implementation.id, -1),
  )
  defer (fixture.reset)(
    prepared,
    @fixture.ResetContext::new(-1, implementation.id),
  )
  run_sequence(implementation, prepared, steps)
}

///|
/// Runs `steps` operations of `implementation` on `prepared`, threading the
/// sticky context, and stops early when an operation returns no context.
async fn[Prepared, Output, Context] run_sequence(
  implementation : Implementation[Prepared, Output, Context],
  prepared : Prepared,
  steps : Int,
) -> Array[@model.OperationResult[Output, Context]] {
  let results = []
  let mut context = (implementation.initial_context)()
  for step_id = 0; step_id < steps; step_id = step_id + 1 {
    let result = execute_operation(implementation, prepared, context)
    results.push(result)
    match result.next_context {
      Some(next_context) => context = next_context
      None => break
    }
  }
  results
}

///|
/// Validation run for `ValidationCoverage::EveryMeasurement`: the sequence
/// runs on the prepared value the next measured batch will use (the cached
/// value for long-lived setup, a value prepared with the batch's sample
/// context otherwise) and that value is reset afterwards, outside any timed
/// region. Returns the results and the updated long-lived cache.
async fn[Scale, Input, Prepared, Output, Context] measurement_validation_sequence(
  fixture : @fixture.Fixture[Scale, Input, Prepared],
  input : Input,
  implementation : Implementation[Prepared, Output, Context],
  steps : Int,
  sample_id : Int,
  cached_prepared : Prepared?,
) -> (Array[@model.OperationResult[Output, Context]], Prepared?) {
  let long_lived = is_long_lived(fixture.setup_policy.frequency)
  let prepared = match cached_prepared {
    Some(prepared) if long_lived => prepared
    _ =>
      (fixture.prepare)(
        (fixture.clone_input)(input),
        implementation.id,
        @fixture.SampleContext::new(sample_id, implementation.id, sample_id),
      )
  }
  let results = run_sequence(implementation, prepared, steps)
  (fixture.reset)(
    prepared,
    @fixture.ResetContext::new(sample_id, implementation.id),
  )
  (results, if long_lived { Some(prepared) } else { cached_prepared })
}

///|
fn[Input, Expected, Output, Context] reference_expected_sequence(
  oracle : @experiment.ReferenceOracle[Input, Expected, Output, Context],
  input : Input,
  steps : Int,
) -> Array[@model.OperationResult[Expected, Context]] {
  let results = []
  let mut context = (oracle.initial_context)()
  for step_id = 0; step_id < steps; step_id = step_id + 1 {
    let result = (oracle.compute_expected)(input, step_id, context)
    results.push(result)
    match result.next_context {
      Some(next_context) => context = next_context
      None => break
    }
  }
  results
}

///|
fn[Input, Expected, Output, Context] validation_steps(
  case_steps : Int,
  oracle : @experiment.OracleSpec[Input, Expected, Output, Context],
  input : Input,
) -> Result[Int, BenchConfigError] {
  match oracle {
    @experiment.OracleSpec::Reference(reference)
    | @experiment.OracleSpec::ReferenceAndRelational(reference, _) => {
      let steps = (reference.sequence_length)(input)
      if steps <= 0 {
        Err(InvalidOracleSequenceLength(steps))
      } else if steps != case_steps {
        Err(OracleSequenceLengthMismatch(case_steps, steps))
      } else {
        Ok(steps)
      }
    }
    @experiment.OracleSpec::Relational(_) => Ok(case_steps)
  }
}

///|
fn[Value] status_from_outcome(
  outcome : @model.ExecutionOutcome[Value],
) -> @model.ValidationStatus? {
  match outcome {
    Unsupported(reason) => Some(Unsupported(reason))
    ParseFailure(reason) => Some(InfrastructureFailure(reason))
    Aborted(code, stderr) =>
      Some(
        InfrastructureFailure("worker exit " + code.to_string() + ": " + stderr),
      )
    Timeout(milliseconds, reason) =>
      Some(
        InfrastructureFailure(
          "timeout after " + milliseconds.to_string() + "ms: " + reason,
        ),
      )
    ExpectedDifference(reason) => Some(ExpectedDifference(reason))
    _ => None
  }
}

///|
fn[Input, Prepared, Expected, Output, Context] detailed_reference_validation(
  case_id : String,
  input : Input,
  dataset_id : Int,
  scale_text : String,
  fingerprint : String,
  implementation : Implementation[Prepared, Output, Context],
  oracle : @experiment.ReferenceOracle[Input, Expected, Output, Context],
  step_id : Int,
  expected : @model.OperationResult[Expected, Context],
  actual : @model.OperationResult[Output, Context],
  descriptor : @model.CaseDescriptor,
  output_text : (Output) -> String,
  context_text : (Context) -> String,
  replay : @model.ReplaySpec,
  measurement : @model.MeasurementKey?,
) -> @model.Validation {
  let status = match status_from_outcome(actual.outcome) {
    Some(status) => status
    None => (oracle.validate)(input, step_id, expected.outcome, actual.outcome)
  }
  let context = match actual.next_context {
    Some(next_context) => context_text(next_context)
    None => descriptor.context
  }
  @model.Validation::detailed(
    status,
    oracle.id,
    implementation.id,
    scale_text,
    {
      case_id,
      dataset_id,
      step_id,
      operation: descriptor.operation,
      operands: descriptor.operands,
      context,
      rounding: descriptor.rounding,
      expected: outcome_text(expected.outcome, oracle.expected_text),
      actual: outcome_text(actual.outcome, output_text),
      expected_kind: expected.outcome.kind(),
      actual_kind: actual.outcome.kind(),
      expected_flags: expected.outcome.flags(),
      actual_flags: actual.outcome.flags(),
      trap: trap_text(actual.outcome),
      stderr: actual.stderr,
      exit_code: actual.exit_code,
      fingerprint,
      implementation_version: implementation.version,
      replay,
    },
    measurement?,
  )
}

///|
fn status_is_failure(status : @model.ValidationStatus) -> Bool {
  match status {
    Invalid(_) | InfrastructureFailure(_) => true
    _ => false
  }
}

///|
async fn[Scale, Input, Prepared, Expected, Output, Context] minimize_failure(
  fixture : @fixture.Fixture[Scale, Input, Prepared],
  implementation : Implementation[Prepared, Output, Context],
  oracle : @experiment.ReferenceOracle[Input, Expected, Output, Context],
  shrinker : @experiment.Shrinker[Input],
  initial : Input,
  failing_step : Int,
) -> (Input, Array[String]) {
  let mut current = initial
  let path = []
  let mut attempts = 0
  while attempts < shrinker.max_steps {
    let mut reduced = false
    for candidate in (shrinker.candidates)(current) {
      attempts += 1
      let steps = (oracle.sequence_length)(candidate)
      if steps <= 0 || steps != (oracle.sequence_length)(current) {
        continue
      }
      let expected = reference_expected_sequence(oracle, candidate, steps)
      let actual = validation_sequence(
        fixture, candidate, implementation, steps,
      )
      if expected.length() > failing_step && actual.length() > failing_step {
        let status = match status_from_outcome(actual[failing_step].outcome) {
          Some(status) => status
          None =>
            (oracle.validate)(
              candidate,
              failing_step,
              expected[failing_step].outcome,
              actual[failing_step].outcome,
            )
        }
        if status_is_failure(status) {
          current = candidate
          path.push((shrinker.text)(candidate))
          reduced = true
          break
        }
      }
      if attempts >= shrinker.max_steps {
        break
      }
    }
    if !reduced {
      break
    }
  }
  (current, path)
}

///|
async fn[Scale, Input, Prepared, Output, Context] minimize_relational_failure(
  fixture : @fixture.Fixture[Scale, Input, Prepared],
  left_implementation : Implementation[Prepared, Output, Context],
  right_implementation : Implementation[Prepared, Output, Context],
  oracle : @experiment.RelationalOracle[Input, Output],
  shrinker : @experiment.Shrinker[Input],
  initial : Input,
  failing_step : Int,
) -> (Input, Array[String]) {
  let mut current = initial
  let path = []
  let mut attempts = 0
  while attempts < shrinker.max_steps {
    let mut reduced = false
    for candidate in (shrinker.candidates)(current) {
      attempts += 1
      let steps = failing_step + 1
      let left = validation_sequence(
        fixture, candidate, left_implementation, steps,
      )
      let right = validation_sequence(
        fixture, candidate, right_implementation, steps,
      )
      if left.length() > failing_step && right.length() > failing_step {
        let status = match status_from_outcome(right[failing_step].outcome) {
          Some(status) => status
          None =>
            (oracle.validate_pair)(
              candidate,
              failing_step,
              left_implementation.id,
              left[failing_step].outcome,
              right_implementation.id,
              right[failing_step].outcome,
            )
        }
        if status_is_failure(status) {
          current = candidate
          path.push((shrinker.text)(candidate))
          reduced = true
          break
        }
      }
      if attempts >= shrinker.max_steps {
        break
      }
    }
    if !reduced {
      break
    }
  }
  (current, path)
}

///|
priv struct ValidationTally {
  mut total : Int
  mut measurement : Int
  mut passed : Int
  mut failed : Int
  mut unsupported : Int
  mut expected_difference : Int
}

///|
fn ValidationTally::new() -> ValidationTally {
  {
    total: 0,
    measurement: 0,
    passed: 0,
    failed: 0,
    unsupported: 0,
    expected_difference: 0,
  }
}

///|
fn ValidationTally::count(
  self : ValidationTally,
  validation : @model.Validation,
) -> Unit {
  self.total += 1
  if validation.measurement is Some(_) {
    self.measurement += 1
  }
  match validation.status {
    Valid => self.passed += 1
    Invalid(_) | InfrastructureFailure(_) => self.failed += 1
    Unsupported(_) | Skipped(_) => self.unsupported += 1
    ExpectedDifference(_) => self.expected_difference += 1
  }
}

///|
priv struct BatchResult[Prepared] {
  elapsed_us : Double
  valid : Bool
  cached_prepared : Prepared?
}

///|
fn is_long_lived(frequency : @model.SetupFrequency) -> Bool {
  match frequency {
    PerRun | PerDataset | PerImplementation => true
    PerSample | PerBatch | PerIteration => false
  }
}

///|
async fn[Scale, Input, Prepared, Output, Context, State, SinkValue] run_batch(
  fixture : @fixture.Fixture[Scale, Input, Prepared],
  input : Input,
  implementation : Implementation[Prepared, Output, Context],
  sink : OutputSink[Output, State, SinkValue],
  iterations : Int,
  sample_id : Int,
  cached_prepared : Prepared?,
  bench : @bench.Bench,
) -> BatchResult[Prepared] {
  let frequency = fixture.setup_policy.frequency
  let state = (sink.initial)()
  let mut current_state = state
  let mut context = (implementation.initial_context)()
  let mut valid = true
  let mut prepared_cache = cached_prepared
  let included = fixture.setup_policy.timing is IncludedInMeasurement
  if frequency is PerIteration {
    let mut elapsed = 0.0
    let batch_timestamp = if included {
      (implementation.synchronize)()
      Some(@bench.monotonic_clock_start())
    } else {
      None
    }
    for _ in 0..<iterations {
      let prepared = (fixture.prepare)(
        (fixture.clone_input)(input),
        implementation.id,
        @fixture.SampleContext::new(sample_id, implementation.id, sample_id),
      )
      let operation_timestamp = if included {
        None
      } else {
        (implementation.synchronize)()
        Some(@bench.monotonic_clock_start())
      }
      let result = execute_operation(implementation, prepared, context)
      match result.outcome.value_option() {
        Some(output) => current_state = (sink.fold)(current_state, output)
        None => valid = false
      }
      if !included {
        (implementation.synchronize)()
        elapsed += @bench.monotonic_clock_end(operation_timestamp.unwrap())
      }
      (fixture.reset)(
        prepared,
        @fixture.ResetContext::new(sample_id, implementation.id),
      )
      match result.next_context {
        Some(next_context) => context = next_context
        None => {
          valid = false
          break
        }
      }
    }
    if included {
      (implementation.synchronize)()
      elapsed = @bench.monotonic_clock_end(batch_timestamp.unwrap())
    }
    let sink_value = (sink.finish)(current_state)
    @bench.Bench::keep(bench, sink_value)
    { elapsed_us: elapsed, valid, cached_prepared: None, }
  } else {
    let batch_timestamp = if included {
      (implementation.synchronize)()
      Some(@bench.monotonic_clock_start())
    } else {
      None
    }
    let prepared = match prepared_cache {
      Some(prepared) => prepared
      None => {
        let prepared = (fixture.prepare)(
          (fixture.clone_input)(input),
          implementation.id,
          @fixture.SampleContext::new(sample_id, implementation.id, sample_id),
        )
        if is_long_lived(frequency) {
          prepared_cache = Some(prepared)
        }
        prepared
      }
    }
    let operation_timestamp = if included {
      None
    } else {
      (implementation.synchronize)()
      Some(@bench.monotonic_clock_start())
    }
    for _ in 0..<iterations {
      let result = execute_operation(implementation, prepared, context)
      match result.outcome.value_option() {
        Some(output) => current_state = (sink.fold)(current_state, output)
        None => valid = false
      }
      match result.next_context {
        Some(next_context) => context = next_context
        None => {
          valid = false
          break
        }
      }
    }
    let mut elapsed = 0.0
    if !included {
      (implementation.synchronize)()
      elapsed = @bench.monotonic_clock_end(operation_timestamp.unwrap())
    }
    if !is_long_lived(frequency) {
      (fixture.reset)(
        prepared,
        @fixture.ResetContext::new(sample_id, implementation.id),
      )
    }
    if included {
      (implementation.synchronize)()
      elapsed = @bench.monotonic_clock_end(batch_timestamp.unwrap())
    }
    let sink_value = (sink.finish)(current_state)
    @bench.Bench::keep(bench, sink_value)
    { elapsed_us: elapsed, valid, cached_prepared: prepared_cache, }
  }
}

///|
async fn[Scale, Input, Prepared, Output, Context, State, SinkValue] calibrate_batch(
  fixture : @fixture.Fixture[Scale, Input, Prepared],
  input : Input,
  implementation : Implementation[Prepared, Output, Context],
  sink : OutputSink[Output, State, SinkValue],
  protocol : @model.CalibrationProtocol,
  cached_prepared : Prepared?,
  bench : @bench.Bench,
) -> (BatchResult[Prepared], Int, Int) {
  let maximum = protocol.max_batch_iterations.max(1)
  let mut iterations = protocol.min_batch_iterations.max(1).min(maximum)
  let mut retries = 0
  let mut batch = run_batch(
    fixture, input, implementation, sink, iterations, -2, cached_prepared, bench,
  )
  while batch.valid &&
        batch.elapsed_us < protocol.target_batch_time_us &&
        batch.elapsed_us < protocol.max_sample_time_us &&
        iterations < maximum {
    let estimated = if batch.elapsed_us <= 0.0 {
      iterations * 10
    } else {
      (iterations.to_double() * protocol.target_batch_time_us / batch.elapsed_us)
      .ceil()
      .to_int()
    }
    let next_iterations = estimated.max(iterations + 1).min(maximum)
    if next_iterations == iterations {
      break
    }
    iterations = next_iterations
    retries += 1
    batch = run_batch(
      fixture,
      input,
      implementation,
      sink,
      iterations,
      -2 - retries,
      batch.cached_prepared,
      bench,
    )
  }
  (batch, iterations, retries)
}

///|
fn measurement_order(
  policy : @model.OrderPolicy,
  implementation_count : Int,
  block_id : Int,
  run_seed : UInt64,
) -> Array[Int] {
  match policy {
    FixedOrder => Array::makei(implementation_count, index => index)
    BalancedBlocks(order_seed) => {
      let offset = if implementation_count <= 0 {
        0
      } else {
        ((order_seed ^ run_seed) % implementation_count.to_uint64()).to_int()
      }
      balanced_order(implementation_count, block_id + offset)
    }
  }
}

///|
/// Number of datasets materialized for each scale:
/// `FixedDatasetRepeatedMeasurements` uses one, `MultipleDatasetsSingleMeasurement`
/// one per block and `HierarchicalDatasetsAndRepeats` one per
/// `repeats_per_dataset` consecutive blocks.
fn datasets_per_scale(protocol : @model.RunProtocol) -> Int {
  let blocks = protocol.exploratory_samples + protocol.confirmatory_samples
  (blocks / blocks_per_dataset(protocol).max(1)).max(1)
}

///|
/// Number of consecutive blocks (exploratory first, then confirmatory) that
/// measure the same dataset.
fn blocks_per_dataset(protocol : @model.RunProtocol) -> Int {
  match protocol.experiment_design {
    FixedDatasetRepeatedMeasurements =>
      protocol.exploratory_samples + protocol.confirmatory_samples
    MultipleDatasetsSingleMeasurement => 1
    HierarchicalDatasetsAndRepeats => protocol.repeats_per_dataset
  }
}

///|
/// Emits one validation per comparable step of `actual` against the reference
/// `expected`, counts it and, on failure, emits a minimized
/// `ValidationFailure`.
async fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] emit_reference_validations(
  case : DifferentialCase[
    Scale,
    Input,
    Prepared,
    Expected,
    Output,
    Context,
    State,
    SinkValue,
  ],
  reference : @experiment.ReferenceOracle[Input, Expected, Output, Context],
  sink : @event.ObservationSink,
  tally : ValidationTally,
  seed : UInt64,
  input : Input,
  dataset_id : Int,
  scale_text : String,
  fingerprint : String,
  implementation : Implementation[Prepared, Output, Context],
  expected : Array[@model.OperationResult[Expected, Context]],
  actual : Array[@model.OperationResult[Output, Context]],
  measurement : @model.MeasurementKey?,
) -> Unit {
  let comparable_steps = expected.length().min(actual.length())
  for step_id = 0; step_id < comparable_steps; step_id = step_id + 1 {
    let validation = detailed_reference_validation(
      case.id,
      input,
      dataset_id,
      scale_text,
      fingerprint,
      implementation,
      reference,
      step_id,
      expected[step_id],
      actual[step_id],
      (case.describe)(input, step_id),
      case.output_text,
      case.context_text,
      (case.replay)(input, implementation.id),
      measurement,
    )
    (sink.emit_validation)(validation)
    tally.count(validation)
    if status_is_failure(validation.status) {
      let (minimal_input, shrink_path) = match case.shrinker {
        Some(shrinker) =>
          minimize_failure(
            case.fixture,
            implementation,
            reference,
            shrinker,
            input,
            step_id,
          )
        None => (input, [])
      }
      (sink.emit_failure)(
        @model.ValidationFailure::new(
          validation,
          seed,
          scale_text,
          fingerprint,
          (case.fixture.fingerprint)(minimal_input),
          shrink_path,
          (case.input_text)(minimal_input),
        ),
      )
    }
  }
  if expected.length() != case.sequence_length ||
    actual.length() != case.sequence_length {
    let expected_count = expected.length()
    let actual_count = actual.length()
    let validation = @model.Validation::new(
      @model.ValidationStatus::Invalid(
        "sequence length mismatch: configured \{case.sequence_length} steps, oracle produced \{expected_count}, implementation produced \{actual_count}",
      ),
      reference.id,
      implementation.id,
      scale_text,
      measurement?,
    )
    (sink.emit_validation)(validation)
    tally.count(validation)
  }
}

///|
/// Emits one relational validation per comparable step of the `left` and
/// `right` sequences, attributed to the right-hand implementation, counts it
/// and, on failure, emits a minimized `ValidationFailure`.
async fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] emit_relational_validations(
  case : DifferentialCase[
    Scale,
    Input,
    Prepared,
    Expected,
    Output,
    Context,
    State,
    SinkValue,
  ],
  relational : @experiment.RelationalOracle[Input, Output],
  sink : @event.ObservationSink,
  tally : ValidationTally,
  seed : UInt64,
  input : Input,
  dataset_id : Int,
  scale_text : String,
  fingerprint : String,
  left_index : Int,
  left : Array[@model.OperationResult[Output, Context]],
  right_index : Int,
  right : Array[@model.OperationResult[Output, Context]],
  measurement : @model.MeasurementKey?,
) -> Unit {
  let left_implementation = case.implementations[left_index]
  let right_implementation = case.implementations[right_index]
  let comparable_steps = left.length().min(right.length())
  for step_id = 0; step_id < comparable_steps; step_id = step_id + 1 {
    let status = match status_from_outcome(right[step_id].outcome) {
      Some(status) => status
      None =>
        (relational.validate_pair)(
          input,
          step_id,
          left_implementation.id,
          left[step_id].outcome,
          right_implementation.id,
          right[step_id].outcome,
        )
    }
    let descriptor = (case.describe)(input, step_id)
    let right_context = match right[step_id].next_context {
      Some(context) => (case.context_text)(context)
      None => descriptor.context
    }
    let validation = @model.Validation::detailed(
      status,
      relational.id,
      right_implementation.id,
      scale_text,
      {
        case_id: case.id,
        dataset_id,
        step_id,
        operation: descriptor.operation,
        operands: descriptor.operands,
        context: right_context,
        rounding: descriptor.rounding,
        expected: outcome_text(left[step_id].outcome, case.output_text),
        actual: outcome_text(right[step_id].outcome, case.output_text),
        expected_kind: left[step_id].outcome.kind(),
        actual_kind: right[step_id].outcome.kind(),
        expected_flags: left[step_id].outcome.flags(),
        actual_flags: right[step_id].outcome.flags(),
        trap: trap_text(right[step_id].outcome),
        stderr: right[step_id].stderr,
        exit_code: right[step_id].exit_code,
        fingerprint,
        implementation_version: right_implementation.version,
        replay: (case.replay)(input, right_implementation.id),
      },
      measurement?,
    )
    (sink.emit_validation)(validation)
    tally.count(validation)
    if status_is_failure(status) {
      let (minimal_input, shrink_path) = match case.shrinker {
        Some(shrinker) =>
          minimize_relational_failure(
            case.fixture,
            left_implementation,
            right_implementation,
            relational,
            shrinker,
            input,
            step_id,
          )
        None => (input, [])
      }
      (sink.emit_failure)(
        @model.ValidationFailure::new(
          validation,
          seed,
          scale_text,
          fingerprint,
          (case.fixture.fingerprint)(minimal_input),
          shrink_path,
          (case.input_text)(minimal_input),
        ),
      )
    }
  }
}

///|
async fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] run_case_internal(
  case : DifferentialCase[
    Scale,
    Input,
    Prepared,
    Expected,
    Output,
    Context,
    State,
    SinkValue,
  ],
  protocol : @model.RunProtocol,
  environment : @model.EnvironmentSnapshot,
  sink : @event.ObservationSink,
  seed : UInt64,
) -> @model.RunSummary {
  let bench = @bench.Bench()
  let mut observation_count = 0
  let mut calibration_count = 0
  let tally = ValidationTally::new()
  let setup_policy = case.fixture.setup_policy
  let implementation_count = case.implementations.length()
  let dataset_count = datasets_per_scale(protocol)
  let dataset_blocks = blocks_per_dataset(protocol)
  for scale_index = 0
      scale_index < case.scales.length()
      scale_index = scale_index + 1 {
    let scale = case.scales[scale_index]
    let scale_text = (case.scale_text)(scale)
    let batch_iterations = Array::makei(implementation_count, _ => {
      protocol.calibration.min_batch_iterations.max(1)
    })
    for dataset_index = 0
        dataset_index < dataset_count
        dataset_index = dataset_index + 1 {
      // Dataset ids are unique within the run; with one dataset per scale
      // (FixedDatasetRepeatedMeasurements) the id is the scale index.
      let dataset_id = scale_index * dataset_count + dataset_index
      let first_block = dataset_index * dataset_blocks
      let end_block = first_block + dataset_blocks
      let key = @model.DatasetKey::new(scale, dataset_id)
      let generation_context = @model.GenerationContext::new(
        seed,
        "default",
        case.id,
        key,
        case.fixture.id,
        case.fixture.version,
      )
      let input = (case.fixture.materialize)(generation_context)
      let fingerprint = (case.fixture.fingerprint)(input)
      let validate_dataset = match protocol.validation_coverage {
        EveryDataset | EveryMeasurement => true
        ConfirmatoryOnly => end_block > protocol.exploratory_samples
      }
      let steps = if validate_dataset {
        match validation_steps(case.sequence_length, case.oracle, input) {
          Ok(steps) => steps
          Err(error) => raise RunConfigError([error])
        }
      } else {
        case.sequence_length
      }
      let expected_sequence : Array[@model.OperationResult[Expected, Context]] = []
      let actual_sequences = []
      if validate_dataset {
        for implementation in case.implementations {
          actual_sequences.push(
            validation_sequence(case.fixture, input, implementation, steps),
          )
        }
        match case.oracle {
          Reference(reference) | ReferenceAndRelational(reference, _) => {
            expected_sequence.append(
              reference_expected_sequence(reference, input, steps),
            )
            for implementation_index = 0
                implementation_index < implementation_count
                implementation_index = implementation_index + 1 {
              emit_reference_validations(
                case,
                reference,
                sink,
                tally,
                seed,
                input,
                dataset_id,
                scale_text,
                fingerprint,
                case.implementations[implementation_index],
                expected_sequence,
                actual_sequences[implementation_index],
                None,
              )
            }
          }
          Relational(_) => ()
        }
        match case.oracle {
          Relational(relational) | ReferenceAndRelational(_, relational) =>
            for left_index = 0
                left_index < implementation_count
                left_index = left_index + 1 {
              for right_index = left_index + 1
                  right_index < implementation_count
                  right_index = right_index + 1 {
                emit_relational_validations(
                  case,
                  relational,
                  sink,
                  tally,
                  seed,
                  input,
                  dataset_id,
                  scale_text,
                  fingerprint,
                  left_index,
                  actual_sequences[left_index],
                  right_index,
                  actual_sequences[right_index],
                  None,
                )
              }
            }
          Reference(_) => ()
        }
      }
      // The prepared cache belongs to this dataset: `prepare` is keyed by
      // input and implementation, so long-lived setup is redone per dataset.
      let prepared_cache : Array[Prepared?] = Array::makei(
        implementation_count,
        _ => None,
      )
      if dataset_index == 0 {
        // Warmup and calibration run once per scale, on its first dataset.
        for implementation_index = 0
            implementation_index < implementation_count
            implementation_index = implementation_index + 1 {
          let implementation = case.implementations[implementation_index]
          let mut warmup_id = 0
          let mut warmup_elapsed_us = 0.0
          let warmup_target_us = protocol.warmup_time_us.unwrap_or(0.0)
          let warmup_limit = protocol.warmup_iterations.max(
            protocol.calibration.max_batch_iterations.max(1),
          )
          while (
                  warmup_id < protocol.warmup_iterations ||
                  warmup_elapsed_us < warmup_target_us
                ) &&
                warmup_id < warmup_limit {
            let batch = run_batch(
              case.fixture,
              input,
              implementation,
              case.output_sink,
              1,
              -1000 - warmup_id,
              prepared_cache[implementation_index],
              bench,
            )
            prepared_cache[implementation_index] = batch.cached_prepared
            warmup_elapsed_us += batch.elapsed_us
            warmup_id += 1
          }
          match prepared_cache[implementation_index] {
            Some(prepared) =>
              (case.fixture.reset)(
                prepared,
                @fixture.ResetContext::new(-3, implementation.id),
              )
            None => ()
          }
          let (calibration, calibration_iterations, retries) = calibrate_batch(
            case.fixture,
            input,
            implementation,
            case.output_sink,
            protocol.calibration,
            prepared_cache[implementation_index],
            bench,
          )
          batch_iterations[implementation_index] = calibration_iterations
          prepared_cache[implementation_index] = calibration.cached_prepared
          match prepared_cache[implementation_index] {
            Some(prepared) =>
              (case.fixture.reset)(
                prepared,
                @fixture.ResetContext::new(-2, implementation.id),
              )
            None => ()
          }
          (sink.emit_calibration)(
            @model.CalibrationEvent::new(
              implementation.id,
              dataset_id,
              calibration_iterations,
              calibration.elapsed_us,
              protocol.calibration.target_batch_time_us,
              retries,
            ),
          )
          calibration_count += 1
        }
        if protocol.calibration.batch_policy
          is @model.BatchPolicy::SharedBatchSize &&
          !batch_iterations.is_empty() {
          let mut shared_iterations = batch_iterations[0]
          for iterations in batch_iterations {
            shared_iterations = shared_iterations.min(iterations)
          }
          for index = 0; index < batch_iterations.length(); index = index + 1 {
            batch_iterations[index] = shared_iterations
          }
        }
      } else if is_long_lived(setup_policy.frequency) {
        // Later datasets prepare long-lived setup before their first block,
        // outside every timed region, as warmup and calibration do for the
        // first dataset.
        for implementation_index = 0
            implementation_index < implementation_count
            implementation_index = implementation_index + 1 {
          let implementation = case.implementations[implementation_index]
          prepared_cache[implementation_index] = Some(
            (case.fixture.prepare)(
              (case.fixture.clone_input)(input),
              implementation.id,
              @fixture.SampleContext::new(-4, implementation.id, -4),
            ),
          )
        }
      }
      for block_id = first_block; block_id < end_block; block_id = block_id + 1 {
        let exploratory = block_id < protocol.exploratory_samples
        let repetition_id = if exploratory {
          block_id
        } else {
          block_id - protocol.exploratory_samples
        }
        let sample_id = if exploratory {
          -100000 - repetition_id
        } else {
          repetition_id
        }
        let phase = if exploratory {
          @model.ObservationPhase::Exploratory
        } else {
          @model.ObservationPhase::Confirmatory
        }
        let order = measurement_order(
          protocol.order_policy,
          implementation_count,
          block_id,
          seed,
        )
        for position = 0; position < order.length(); position = position + 1 {
          let implementation_index = order[position]
          let implementation = case.implementations[implementation_index]
          if protocol.validation_coverage is EveryMeasurement {
            let (actual, cached_prepared) = measurement_validation_sequence(
              case.fixture,
              input,
              implementation,
              steps,
              sample_id,
              prepared_cache[implementation_index],
            )
            prepared_cache[implementation_index] = cached_prepared
            let measurement = Some(
              @model.MeasurementKey::new(dataset_id, repetition_id, block_id),
            )
            match case.oracle {
              Reference(reference) | ReferenceAndRelational(reference, _) =>
                emit_reference_validations(
                  case, reference, sink, tally, seed, input, dataset_id, scale_text,
                  fingerprint, implementation, expected_sequence, actual, measurement,
                )
              Relational(_) => ()
            }
            match case.oracle {
              Relational(relational) | ReferenceAndRelational(_, relational) =>
                for other_index = 0
                    other_index < implementation_count
                    other_index = other_index + 1 {
                  if other_index != implementation_index {
                    emit_relational_validations(
                      case,
                      relational,
                      sink,
                      tally,
                      seed,
                      input,
                      dataset_id,
                      scale_text,
                      fingerprint,
                      other_index,
                      actual_sequences[other_index],
                      implementation_index,
                      actual,
                      measurement,
                    )
                  }
                }
              Reference(_) => ()
            }
          }
          let iterations = batch_iterations[implementation_index]
          let batch = run_batch(
            case.fixture,
            input,
            implementation,
            case.output_sink,
            iterations,
            sample_id,
            prepared_cache[implementation_index],
            bench,
          )
          prepared_cache[implementation_index] = batch.cached_prepared
          (sink.emit_observation)(
            @model.Observation::new(
              case.id,
              implementation.id,
              implementation.version,
              dataset_id,
              repetition_id,
              block_id,
              phase,
              batch.elapsed_us / iterations.to_double(),
              iterations,
              @model.BatchSinkStatus::Kept,
              setup_policy.timing,
              batch.valid,
              setup_frequency=setup_policy.frequency,
              workspace_scope=setup_policy.workspace_scope,
              scale_text~,
            ),
          )
          observation_count += 1
        }
      }
      for implementation_index = 0
          implementation_index < implementation_count
          implementation_index = implementation_index + 1 {
        match prepared_cache[implementation_index] {
          Some(prepared) =>
            (case.fixture.reset)(
              prepared,
              @fixture.ResetContext::new(
                protocol.confirmatory_samples,
                case.implementations[implementation_index].id,
              ),
            )
          None => ()
        }
      }
    }
  }
  let summary = @model.RunSummary::new(
    @model.run_identity(case.id, protocol, seed, environment.provenance),
    observation_count,
    tally.total,
    calibration_count,
    true,
    None,
    passed_count=tally.passed,
    failed_count=tally.failed,
    unsupported_count=tally.unsupported,
    expected_difference_count=tally.expected_difference,
    measurement_validation_count=tally.measurement,
    environment~,
    protocol~,
    seed~,
  )
  let location = (sink.finish)(summary)
  @model.RunSummary::new(
    summary.run_id,
    summary.observation_count,
    summary.validation_count,
    summary.calibration_count,
    summary.complete,
    Some(location),
    passed_count=summary.passed_count,
    failed_count=summary.failed_count,
    unsupported_count=summary.unsupported_count,
    expected_difference_count=summary.expected_difference_count,
    measurement_validation_count=summary.measurement_validation_count,
    environment~,
    protocol~,
    seed~,
  )
}

///|
pub async fn[
  Scale,
  Input,
  Prepared,
  Expected,
  Output,
  Context,
  State,
  SinkValue,
] run(
  plan : ValidatedBenchPlan[
    Scale,
    Input,
    Prepared,
    Expected,
    Output,
    Context,
    State,
    SinkValue,
  ],
  context : RunContext,
) -> @model.RunSummary {
  let errors = setup_errors(plan.case, Some(context.protocol.protocol))
  if !errors.is_empty() {
    raise RunConfigError(errors)
  }
  run_case_internal(
    plan.case,
    context.protocol.protocol,
    context.environment,
    context.sink,
    context.seed,
  )
}
