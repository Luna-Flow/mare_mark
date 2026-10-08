# event API

`Luna-Flow/mare_mark/event` receives what the runner emits. An
`ObservationSink` is a record of five callbacks; the package provides an
in-memory sink, a buffered JSONL sink, a streaming JSONL sink and a fan-out
combinator. The JSONL format is the audit record that reports and replays
read. See the [event design](../design/event.md).

Source: [`src/event/event.mbt`](../../../src/event/event.mbt).

```text
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/event",
}
```

## Sinks

### `ObservationSink`

`ObservationSink` is the interface between the runner and storage.

```mbti
pub struct ObservationSink {
  emit_observation : (@model.Observation) -> Unit
  emit_validation : (@model.Validation) -> Unit
  emit_failure : (@model.ValidationFailure) -> Unit
  emit_calibration : (@model.CalibrationEvent) -> Unit
  finish : (@model.RunSummary) -> String
}
pub fn ObservationSink::new((@model.Observation) -> Unit, (@model.Validation) -> Unit, (@model.CalibrationEvent) -> Unit, (@model.RunSummary) -> String, emit_failure? : (@model.ValidationFailure) -> Unit) -> Self
```

`finish` receives the run summary once, at the end, and returns a location
string that the runner stores in `RunSummary.artifact_location`. Note the
argument order of `new`: observation, validation, calibration, finish, and the
optional failure callback, which defaults to ignoring failures.

```moonbit
test "a counting sink" {
  let count = Ref(0)
  let sink = @event.ObservationSink::new(
    _ => count.val += 1,
    _ => (),
    _ => (),
    summary => "counted://" + summary.run_id,
  )
  (sink.emit_observation)(
    @model.Observation::new("c", "a", "1", 0, 0, 0, Confirmatory, 1.5, 10, Kept, ExcludedFromMeasurement, true),
  )
  inspect(count.val, content="1")
  inspect((sink.finish)(@model.RunSummary::new("r", 1, 0, 0, true, None)), content="counted://r")
}
```

### `InMemorySink`

`InMemorySink` keeps every event in arrays.

```mbti
pub struct InMemorySink {
  observations : Array[@model.Observation]
  validations : Array[@model.Validation]
  failures : Array[@model.ValidationFailure]
  calibrations : Array[@model.CalibrationEvent]
}
pub fn InMemorySink::new() -> Self
pub fn InMemorySink::as_sink(Self) -> ObservationSink
```

`as_sink` appends to the arrays; its `finish` returns
`"memory://run/" + run_id` and does not store the summary.

### `JsonlSink`

`JsonlSink` keeps every event as one JSON line.

```mbti
pub struct JsonlSink {
  lines : Array[String]
}
pub fn JsonlSink::new() -> Self
pub fn JsonlSink::as_sink(Self) -> ObservationSink
pub fn JsonlSink::to_jsonl(Self) -> String
```

`as_sink` appends one line per event, including the summary; its `finish`
returns `"jsonl://memory/" + run_id`. `to_jsonl` joins the lines with `"\n"`,
without a trailing newline.

```moonbit
test "JSONL lines" {
  let jsonl = @event.JsonlSink::new()
  let sink = jsonl.as_sink()
  (sink.emit_calibration)(@model.CalibrationEvent::new("a", 0, 64, 1012.5, 1000.0, 1))
  inspect(
    jsonl.to_jsonl(),
    content="{\"artifact_version\":\"mmka_1\",\"type\":\"calibration\",\"implementation\":\"a\",\"dataset_id\":0,\"batch_iterations\":64,\"elapsed_us\":1012.5,\"target_elapsed_us\":1000,\"retries\":1}",
  )
}
```

### `streaming_jsonl`

`streaming_jsonl` returns a sink that writes every event line immediately.

```mbti
pub fn streaming_jsonl((String) -> Unit, String) -> ObservationSink
```

The first argument receives each line without a newline; the second is the
location returned by `finish`. Use it to append to a file or a pipe as the run
progresses, so that a crash leaves a valid prefix of the stream.

```moonbit
test "stream lines as they happen" {
  let written : Array[String] = []
  let sink = @event.streaming_jsonl(line => written.push(line), "file://events.jsonl")
  let location = (sink.finish)(@model.RunSummary::new("r", 0, 0, 0, true, None))
  inspect(location, content="file://events.jsonl")
  inspect(written[0].contains("\"type\":\"summary\""), content="true")
}
```

### `tee`

`tee` sends every event to two sinks.

```mbti
pub fn tee(ObservationSink, ObservationSink) -> ObservationSink
```

Events go to the left sink first. `finish` calls both and returns the location
of the right sink.

## JSONL records

Every line is an object with `"artifact_version": "mmka_1"` and a `"type"`:

| `type` | Fields |
| --- | --- |
| `observation` | `case`, `implementation`, `implementation_version`, `dataset_id`, `repetition_id`, `block_id`, `phase`, `elapsed_us`, `iterations`, `batch_sink`, `valid` |
| `validation` | `status`, `implementation`, `oracle`, `scale`; with evidence also `case`, `dataset_id`, `step_id`, `operation`, `operands`, `context`, `rounding`, `expected`, `actual`, `expected_kind`, `actual_kind`, `expected_flags`, `actual_flags`, `trap`, `stderr`, `exit_code` (when present), `fingerprint`, `implementation_version`, `replay_command`, `replay_arguments`, `replay_timeout_ms` |
| `validation_failure` | all fields of the validation, plus `seed` (a decimal string), `original_fingerprint`, `minimal_fingerprint`, `shrink_path`, `minimal_input` |
| `calibration` | `implementation`, `dataset_id`, `batch_iterations`, `elapsed_us`, `target_elapsed_us`, `retries` |
| `summary` | `run_id`, `observation_count`, `validation_count`, `calibration_count`, `complete`, `passed_count`, `failed_count`, `unsupported_count`, `expected_difference_count`, and `environment` with `semantic`, `performance` and `provenance` objects when known |

`status` is one of `valid`, `invalid`, `skipped`, `expected_difference`,
`unsupported`, `infrastructure_failure`; the reason strings of the status are
not written. `phase` is `exploratory` or `confirmatory`; `batch_sink` is `kept`
or `discarded:<reason>`. The observation's `setup_timing` is not written.
