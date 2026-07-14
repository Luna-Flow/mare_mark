///|
pub struct ObservationSink {
  emit_observation : (@model.Observation) -> Unit
  emit_validation : (@model.Validation) -> Unit
  emit_failure : (@model.ValidationFailure) -> Unit
  emit_calibration : (@model.CalibrationEvent) -> Unit
  finish : (@model.RunSummary) -> String
}

///|
pub fn ObservationSink::new(
  emit_observation : (@model.Observation) -> Unit,
  emit_validation : (@model.Validation) -> Unit,
  emit_calibration : (@model.CalibrationEvent) -> Unit,
  finish : (@model.RunSummary) -> String,
  emit_failure? : (@model.ValidationFailure) -> Unit = _ => (),
) -> ObservationSink {
  { emit_observation, emit_validation, emit_failure, emit_calibration, finish }
}

///|
pub struct InMemorySink {
  observations : Array[@model.Observation]
  validations : Array[@model.Validation]
  failures : Array[@model.ValidationFailure]
  calibrations : Array[@model.CalibrationEvent]
}

///|
pub fn InMemorySink::new() -> InMemorySink {
  { observations: [], validations: [], failures: [], calibrations: [] }
}

///|
pub fn InMemorySink::as_sink(self : InMemorySink) -> ObservationSink {
  ObservationSink::new(
    observation => self.observations.push(observation),
    validation => self.validations.push(validation),
    calibration => self.calibrations.push(calibration),
    summary => "memory://run/" + summary.run_id,
    emit_failure=failure => self.failures.push(failure),
  )
}

///|
pub struct JsonlSink {
  lines : Array[String]
}

///|
pub fn JsonlSink::new() -> JsonlSink {
  { lines: [] }
}

///|
fn status_name(status : @model.ValidationStatus) -> String {
  match status {
    Valid => "valid"
    Invalid(_) => "invalid"
    Skipped(_) => "skipped"
    ExpectedDifference(_) => "expected_difference"
    Unsupported(_) => "unsupported"
    InfrastructureFailure(_) => "infrastructure_failure"
  }
}

///|
fn validation_json(validation : @model.Validation) -> Json {
  let base : Map[String, Json] = {
    "type": Json::string("validation"),
    "status": Json::string(status_name(validation.status)),
    "implementation": Json::string(validation.implementation_id),
    "oracle": Json::string(validation.oracle_id),
    "scale": Json::string(validation.scale_text),
  }
  match validation.evidence {
    None => Json::object(base)
    Some(evidence) => {
      base["case"] = Json::string(evidence.case_id)
      base["dataset_id"] = Json::number(evidence.dataset_id.to_double())
      base["step_id"] = Json::number(evidence.step_id.to_double())
      base["operation"] = Json::string(evidence.operation)
      base["operands"] = Json::array(evidence.operands.map(Json::string))
      base["context"] = Json::string(evidence.context)
      base["rounding"] = Json::string(evidence.rounding)
      base["expected"] = Json::string(evidence.expected)
      base["actual"] = Json::string(evidence.actual)
      base["expected_kind"] = Json::string(evidence.expected_kind)
      base["actual_kind"] = Json::string(evidence.actual_kind)
      base["expected_flags"] = Json::array(
        evidence.expected_flags.map(Json::string),
      )
      base["actual_flags"] = Json::array(
        evidence.actual_flags.map(Json::string),
      )
      base["trap"] = Json::string(evidence.trap)
      base["stderr"] = Json::string(evidence.stderr)
      match evidence.exit_code {
        Some(exit_code) =>
          base["exit_code"] = Json::number(exit_code.to_double())
        None => ()
      }
      base["fingerprint"] = Json::string(evidence.fingerprint)
      base["implementation_version"] = Json::string(
        evidence.implementation_version,
      )
      base["replay_command"] = Json::string(evidence.replay.command)
      base["replay_arguments"] = Json::array(
        evidence.replay.arguments.map(Json::string),
      )
      base["replay_timeout_ms"] = Json::number(
        evidence.replay.timeout_ms.to_double(),
      )
      Json::object(base)
    }
  }
}

///|
fn failure_json(failure : @model.ValidationFailure) -> Json {
  let validation = validation_json(failure.validation)
  guard validation is Object(fields) else { abort("validation must be object") }
  fields["type"] = Json::string("validation_failure")
  fields["seed"] = Json::string(failure.seed.to_string())
  fields["original_fingerprint"] = Json::string(failure.original_fingerprint)
  fields["minimal_fingerprint"] = Json::string(failure.minimal_fingerprint)
  fields["shrink_path"] = Json::array(failure.shrink_path.map(Json::string))
  fields["minimal_input"] = Json::string(failure.minimal_input)
  Json::object(fields)
}

///|
fn observation_json(observation : @model.Observation) -> Json {
  Json::object({
    "type": Json::string("observation"),
    "case": Json::string(observation.case_id),
    "implementation": Json::string(observation.implementation_id),
    "implementation_version": Json::string(observation.implementation_version),
    "dataset_id": Json::number(observation.dataset_id.to_double()),
    "repetition_id": Json::number(observation.repetition_id.to_double()),
    "block_id": Json::number(observation.block_id.to_double()),
    "phase": Json::string(observation.phase),
    "elapsed_us": Json::number(observation.raw_elapsed_us),
    "iterations": Json::number(observation.iterations.to_double()),
    "valid": Json::boolean(observation.valid),
  })
}

///|
fn calibration_json(calibration : @model.CalibrationEvent) -> Json {
  Json::object({
    "type": Json::string("calibration"),
    "implementation": Json::string(calibration.implementation_id),
    "dataset_id": Json::number(calibration.dataset_id.to_double()),
    "batch_iterations": Json::number(calibration.batch_iterations.to_double()),
    "elapsed_us": Json::number(calibration.elapsed_us),
    "target_elapsed_us": Json::number(calibration.target_elapsed_us),
    "retries": Json::number(calibration.retries.to_double()),
  })
}

///|
fn environment_json(environment : @model.EnvironmentSnapshot) -> Json {
  Json::object({
    "semantic": Json::object({
      "target": Json::string(environment.semantic.target),
      "toolchain": Json::string(environment.semantic.toolchain),
      "compiler_flags": Json::string(environment.semantic.compiler_flags),
      "dtype_abi": Json::string(environment.semantic.dtype_abi),
    }),
    "performance": Json::object({
      "runtime": Json::string(environment.performance.runtime),
      "cpu": Json::string(environment.performance.cpu),
      "device": Json::string(environment.performance.device),
      "concurrency": Json::number(
        environment.performance.concurrency.to_double(),
      ),
      "frequency_policy": Json::string(environment.performance.frequency_policy),
      "gc": Json::string(environment.performance.gc),
      "clock": Json::string(environment.performance.clock),
    }),
    "provenance": Json::object({
      "os": Json::string(environment.provenance.os),
      "hostname": Json::string(environment.provenance.hostname),
      "timestamp": Json::string(environment.provenance.timestamp),
      "revision": Json::string(environment.provenance.revision),
      "run_id": Json::string(environment.provenance.run_id),
    }),
  })
}

///|
fn summary_json(summary : @model.RunSummary) -> Json {
  let fields : Map[String, Json] = {
    "type": Json::string("summary"),
    "run_id": Json::string(summary.run_id),
    "observation_count": Json::number(summary.observation_count.to_double()),
    "validation_count": Json::number(summary.validation_count.to_double()),
    "calibration_count": Json::number(summary.calibration_count.to_double()),
    "complete": Json::boolean(summary.complete),
    "passed_count": Json::number(summary.passed_count.to_double()),
    "failed_count": Json::number(summary.failed_count.to_double()),
    "unsupported_count": Json::number(summary.unsupported_count.to_double()),
    "expected_difference_count": Json::number(
      summary.expected_difference_count.to_double(),
    ),
  }
  match summary.environment {
    Some(environment) => fields["environment"] = environment_json(environment)
    None => ()
  }
  Json::object(fields)
}

///|
pub fn JsonlSink::as_sink(self : JsonlSink) -> ObservationSink {
  ObservationSink::new(
    observation => self.lines.push(observation_json(observation).stringify()),
    validation => self.lines.push(validation_json(validation).stringify()),
    calibration => self.lines.push(calibration_json(calibration).stringify()),
    summary => {
      self.lines.push(summary_json(summary).stringify())
      "jsonl://memory/" + summary.run_id
    },
    emit_failure=failure => self.lines.push(failure_json(failure).stringify()),
  )
}

///|
pub fn streaming_jsonl(
  write_line : (String) -> Unit,
  location : String,
) -> ObservationSink {
  ObservationSink::new(
    observation => write_line(observation_json(observation).stringify()),
    validation => write_line(validation_json(validation).stringify()),
    calibration => write_line(calibration_json(calibration).stringify()),
    summary => {
      write_line(summary_json(summary).stringify())
      location
    },
    emit_failure=failure => write_line(failure_json(failure).stringify()),
  )
}

///|
pub fn JsonlSink::to_jsonl(self : JsonlSink) -> String {
  self.lines.join("\n")
}

///|
pub fn tee(left : ObservationSink, right : ObservationSink) -> ObservationSink {
  ObservationSink::new(
    observation => {
      (left.emit_observation)(observation)
      (right.emit_observation)(observation)
    },
    validation => {
      (left.emit_validation)(validation)
      (right.emit_validation)(validation)
    },
    calibration => {
      (left.emit_calibration)(calibration)
      (right.emit_calibration)(calibration)
    },
    summary => {
      ignore((left.finish)(summary))
      (right.finish)(summary)
    },
    emit_failure=failure => {
      (left.emit_failure)(failure)
      (right.emit_failure)(failure)
    },
  )
}
