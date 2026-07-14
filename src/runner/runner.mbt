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
  { command, build_arguments, decode, timeout_ms, cwd }
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
}

///|
pub fn[Prepared, Output, Context] Implementation::in_process(
  id : String,
  version : String,
  initial_context : () -> Context,
  run : (Prepared, Context) -> @model.OperationResult[Output, Context],
) -> Implementation[Prepared, Output, Context] {
  { id, version, initial_context, execution: InProcess(run) }
}

///|
pub fn[Prepared, Output, Context] Implementation::worker(
  id : String,
  version : String,
  initial_context : () -> Context,
  worker : WorkerSpec[Prepared, Output, Context],
) -> Implementation[Prepared, Output, Context] {
  { id, version, initial_context, execution: Subprocess(worker) }
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
  { initial, fold, finish }
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
  sequence_length : (Input) -> Int
  describe : (Input, Int) -> @model.CaseDescriptor
  input_text : (Input) -> String
  output_text : (Output) -> String
  context_text : (Context) -> String
  shrinker : @experiment.Shrinker[Input]?
  replay : (Input, String) -> @model.ReplaySpec
}

///|
pub fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] DifferentialCase::new(
  id : String,
  fixture : @fixture.Fixture[Scale, Input, Prepared],
  implementations : Array[Implementation[Prepared, Output, Context]],
  output_sink : OutputSink[Output, State, SinkValue],
  oracle : @experiment.OracleSpec[Input, Expected, Output, Context],
  scales : Array[Scale],
  scale_text : (Scale) -> String,
  sequence_length : (Input) -> Int,
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
      let steps = failing_step + 1
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
fn count_status(
  status : @model.ValidationStatus,
  passed : Ref[Int],
  failed : Ref[Int],
  unsupported : Ref[Int],
  expected_difference : Ref[Int],
) -> Unit {
  match status {
    Valid => passed.val += 1
    Invalid(_) | InfrastructureFailure(_) => failed.val += 1
    Unsupported(_) | Skipped(_) => unsupported.val += 1
    ExpectedDifference(_) => expected_difference.val += 1
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
  let timestamp = if included {
    Some(@bench.monotonic_clock_start())
  } else {
    None
  }
  if frequency is PerIteration {
    let operation_timestamp = if included {
      timestamp
    } else {
      Some(@bench.monotonic_clock_start())
    }
    for _ in 0..<iterations {
      let prepared = (fixture.prepare)(
        (fixture.clone_input)(input),
        implementation.id,
        @fixture.SampleContext::new(sample_id, implementation.id, sample_id),
      )
      let result = execute_operation(implementation, prepared, context)
      match result.outcome.value_option() {
        Some(output) => current_state = (sink.fold)(current_state, output)
        None => valid = false
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
    let elapsed = @bench.monotonic_clock_end(operation_timestamp.unwrap())
    let sink_value = (sink.finish)(current_state)
    @bench.Bench::keep(bench, sink_value)
    { elapsed_us: elapsed, valid, cached_prepared: None }
  } else {
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
      timestamp
    } else {
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
    let elapsed = @bench.monotonic_clock_end(operation_timestamp.unwrap())
    if !is_long_lived(frequency) {
      (fixture.reset)(
        prepared,
        @fixture.ResetContext::new(sample_id, implementation.id),
      )
    }
    let sink_value = (sink.finish)(current_state)
    @bench.Bench::keep(bench, sink_value)
    { elapsed_us: elapsed, valid, cached_prepared: prepared_cache }
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
pub async fn[
  Scale,
  Input,
  Prepared,
  Expected,
  Output,
  Context,
  State,
  SinkValue,
] run_case(
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
  ignore(environment)
  let bench = @bench.Bench()
  let mut observation_count = 0
  let mut calibration_count = 0
  let mut validation_count = 0
  let passed_count = Ref(0)
  let failed_count = Ref(0)
  let unsupported_count = Ref(0)
  let expected_difference_count = Ref(0)
  for scale_index = 0
      scale_index < case.scales.length()
      scale_index = scale_index + 1 {
    let scale = case.scales[scale_index]
    let scale_text = (case.scale_text)(scale)
    let key = @model.DatasetKey::new(scale, scale_index)
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
    let steps = (case.sequence_length)(input).max(1)
    let actual_sequences = []
    for implementation in case.implementations {
      actual_sequences.push(
        validation_sequence(case.fixture, input, implementation, steps),
      )
    }
    match case.oracle {
      Reference(reference) | ReferenceAndRelational(reference, _) => {
        let expected = reference_expected_sequence(reference, input, steps)
        for implementation_index = 0
            implementation_index < case.implementations.length()
            implementation_index = implementation_index + 1 {
          let implementation = case.implementations[implementation_index]
          let actual = actual_sequences[implementation_index]
          let comparable_steps = expected.length().min(actual.length())
          for step_id = 0; step_id < comparable_steps; step_id = step_id + 1 {
            let validation = detailed_reference_validation(
              case.id,
              input,
              scale_index,
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
            )
            (sink.emit_validation)(validation)
            validation_count += 1
            count_status(
              validation.status,
              passed_count,
              failed_count,
              unsupported_count,
              expected_difference_count,
            )
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
        }
      }
      Relational(_) => ()
    }
    match case.oracle {
      Relational(relational) | ReferenceAndRelational(_, relational) =>
        for left_index = 0
            left_index < case.implementations.length()
            left_index = left_index + 1 {
          for right_index = left_index + 1
              right_index < case.implementations.length()
              right_index = right_index + 1 {
            let left = actual_sequences[left_index]
            let right = actual_sequences[right_index]
            let comparable_steps = left.length().min(right.length())
            for step_id = 0; step_id < comparable_steps; step_id = step_id + 1 {
              let status = match status_from_outcome(right[step_id].outcome) {
                Some(status) => status
                None =>
                  (relational.validate_pair)(
                    input,
                    step_id,
                    case.implementations[left_index].id,
                    left[step_id].outcome,
                    case.implementations[right_index].id,
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
                case.implementations[right_index].id,
                scale_text,
                {
                  case_id: case.id,
                  dataset_id: scale_index,
                  step_id,
                  operation: descriptor.operation,
                  operands: descriptor.operands,
                  context: right_context,
                  rounding: descriptor.rounding,
                  expected: outcome_text(
                    left[step_id].outcome,
                    case.output_text,
                  ),
                  actual: outcome_text(right[step_id].outcome, case.output_text),
                  expected_kind: left[step_id].outcome.kind(),
                  actual_kind: right[step_id].outcome.kind(),
                  expected_flags: left[step_id].outcome.flags(),
                  actual_flags: right[step_id].outcome.flags(),
                  trap: trap_text(right[step_id].outcome),
                  stderr: right[step_id].stderr,
                  exit_code: right[step_id].exit_code,
                  fingerprint,
                  implementation_version: case.implementations[right_index].version,
                  replay: (case.replay)(
                    input,
                    case.implementations[right_index].id,
                  ),
                },
              )
              (sink.emit_validation)(validation)
              validation_count += 1
              count_status(
                status, passed_count, failed_count, unsupported_count, expected_difference_count,
              )
              if status_is_failure(status) {
                let (minimal_input, shrink_path) = match case.shrinker {
                  Some(shrinker) =>
                    minimize_relational_failure(
                      case.fixture,
                      case.implementations[left_index],
                      case.implementations[right_index],
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
        }
      Reference(_) => ()
    }
    let prepared_cache : Array[Prepared?] = Array::makei(
      case.implementations.length(),
      _ => None,
    )
    let batch_iterations = Array::makei(case.implementations.length(), _ => {
      protocol.calibration.min_batch_iterations.max(1)
    })
    for implementation_index = 0
        implementation_index < case.implementations.length()
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
          scale_index,
          calibration_iterations,
          calibration.elapsed_us,
          protocol.calibration.target_batch_time_us,
          retries,
        ),
      )
      calibration_count += 1
    }
    if protocol.calibration.batch_policy is @model.BatchPolicy::SharedBatchSize &&
      !batch_iterations.is_empty() {
      let mut shared_iterations = batch_iterations[0]
      for iterations in batch_iterations {
        shared_iterations = shared_iterations.min(iterations)
      }
      for index = 0; index < batch_iterations.length(); index = index + 1 {
        batch_iterations[index] = shared_iterations
      }
    }
    for repetition_id = 0
        repetition_id < protocol.exploratory_samples
        repetition_id = repetition_id + 1 {
      let order = measurement_order(
        protocol.order_policy,
        case.implementations.length(),
        repetition_id,
        seed,
      )
      for position = 0; position < order.length(); position = position + 1 {
        let implementation_index = order[position]
        let implementation = case.implementations[implementation_index]
        let iterations = batch_iterations[implementation_index]
        let batch = run_batch(
          case.fixture,
          input,
          implementation,
          case.output_sink,
          iterations,
          -100000 - repetition_id,
          prepared_cache[implementation_index],
          bench,
        )
        prepared_cache[implementation_index] = batch.cached_prepared
        (sink.emit_observation)(
          @model.Observation::new(
            case.id,
            implementation.id,
            implementation.version,
            scale_index,
            repetition_id,
            repetition_id,
            "exploratory",
            batch.elapsed_us / iterations.to_double(),
            iterations,
            "kept",
            case.fixture.setup_policy.timing,
            batch.valid,
          ),
        )
        observation_count += 1
      }
    }
    for repetition_id = 0
        repetition_id < protocol.confirmatory_samples
        repetition_id = repetition_id + 1 {
      let order = measurement_order(
        protocol.order_policy,
        case.implementations.length(),
        repetition_id,
        seed,
      )
      for position = 0; position < order.length(); position = position + 1 {
        let implementation_index = order[position]
        let implementation = case.implementations[implementation_index]
        let iterations = batch_iterations[implementation_index]
        let batch = run_batch(
          case.fixture,
          input,
          implementation,
          case.output_sink,
          iterations,
          repetition_id,
          prepared_cache[implementation_index],
          bench,
        )
        prepared_cache[implementation_index] = batch.cached_prepared
        (sink.emit_observation)(
          @model.Observation::new(
            case.id,
            implementation.id,
            implementation.version,
            scale_index,
            repetition_id,
            repetition_id,
            "confirmatory",
            batch.elapsed_us / iterations.to_double(),
            iterations,
            "kept",
            case.fixture.setup_policy.timing,
            batch.valid,
          ),
        )
        observation_count += 1
      }
    }
    for implementation_index = 0
        implementation_index < case.implementations.length()
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
  let summary = @model.RunSummary::new(
    @model.protocol_identity(protocol) + ":" + case.id,
    observation_count,
    validation_count,
    calibration_count,
    true,
    None,
    passed_count=passed_count.val,
    failed_count=failed_count.val,
    unsupported_count=unsupported_count.val,
    expected_difference_count=expected_difference_count.val,
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
] bench_oracle(
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
  run_case(case, protocol, environment, sink, seed)
}
