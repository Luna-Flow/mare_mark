# event API

## Purpose

`Luna-Flow/mare_mark/event` receives what the runner emits. An
`ObservationSink` is a record of five callbacks; the package provides an
in-memory sink, a buffered JSONL sink, a streaming JSONL sink and a fan-out
combinator. The JSONL format is the audit record that reports and replays
read; `protocol_json` and `protocol_from_json` write and read the run protocol
it contains. See the [event design](../design/event.md).

Source: [`src/event/event.mbt`](../../../src/event/event.mbt),
[`src/event/protocol.mbt`](../../../src/event/protocol.mbt).

## Importing

Add the packages to the `moon.pkg` of the package that uses them:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/runner",
  "moonbitlang/core/json",
}
```

The examples on this page call them through their default aliases (`@model`,
`@event`, `@runner`, `@json`); `runner` is needed only for the protocol
presets, and `moonbitlang/core/json` only to parse JSON text.

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

## Protocol objects

### `protocol_json`

`protocol_json` encodes every field of a run protocol as a JSON object.

```mbti
pub fn protocol_json(@model.RunProtocol) -> Json
```

This is the `protocol` object of a JSONL `summary` line. The keys are the
field names of `RunProtocol` and, nested under `calibration`, of
`CalibrationProtocol`. Enums are their `text()` tags, `warmup_time_us` is
`null` when absent, and `order_policy` is `{"kind":"fixed_order"}` or
`{"kind":"balanced_blocks","seed":"<decimal>"}`; the seed is a string because
a JSON number cannot hold every `UInt64`. A double that is not finite is
written as the string `"NaN"`, `"Infinity"` or `"-Infinity"`, and `-0.0` as
`-0`, so the object keeps every value exactly.

```moonbit
test "protocol as JSON" {
  let protocol = @runner.ProtocolPreset::RegressionGate.validated().protocol
  let json = @event.protocol_json(protocol).stringify()
  inspect(json.contains("\"experiment_design\":\"hierarchical_datasets_and_repeats\""), content="true")
  inspect(json.contains("\"order_policy\":{\"kind\":\"balanced_blocks\",\"seed\":\"1\"}"), content="true")
  inspect(json.contains("\"repeats_per_dataset\":5"), content="true")
}
```

### `protocol_from_json`

`protocol_from_json` decodes a `protocol` object back into the protocol.

```mbti
pub fn protocol_from_json(Json) -> Result[@model.RunProtocol, String]
```

It reverses `protocol_json` exactly, so the decoded protocol has the same
`@model.protocol_identity` as the encoded one. Every field is required except
`repeats_per_dataset`, which records written before it existed omit; it is
then `1`, the value those runs used. Unknown keys are ignored. An error
names the offending field, for example
`protocol.calibration.batch_policy: unknown value 'x'` or
`protocol.warmup_iterations: expected an Int`. Integers must be whole numbers
in the `Int` range, and the block-order seed must be the canonical decimal
text of a `UInt64`.

```moonbit
test "protocol round trip" {
  let protocol = @runner.ProtocolPreset::Development.validated().protocol
  let decoded = @event.protocol_from_json(@event.protocol_json(protocol)).unwrap()
  inspect(@model.protocol_identity(decoded) == @model.protocol_identity(protocol), content="true")
  let broken = @json.parse("{\"experiment_design\":\"sometimes\"}")
  inspect(@event.protocol_from_json(broken) is Err("protocol.calibration: missing"), content="true")
}
```

## JSONL records

Every line is an object with `"artifact_version": "mmka_1"` and a `"type"`:

| `type` | Fields |
| --- | --- |
| `observation` | `case`, `implementation`, `implementation_version`, `dataset_id`, `repetition_id`, `block_id`, `phase`, `elapsed_us`, `iterations`, `batch_sink`, `setup_timing`, `valid`; `setup_frequency` and `workspace_scope` when recorded; `scale` when the scale text is not empty |
| `validation` | `status`, `reason` (for every status except `valid`), `implementation`, `oracle`, `scale`; for a measurement validation also `validation_scope` (`"measurement"`), `repetition_id` and `block_id`; with evidence also `case`, `dataset_id`, `step_id`, `operation`, `operands`, `context`, `rounding`, `expected`, `actual`, `expected_kind`, `actual_kind`, `expected_flags`, `actual_flags`, `trap`, `stderr`, `exit_code` (when present), `fingerprint`, `implementation_version`, `replay_command`, `replay_arguments`, `replay_timeout_ms` (a measurement validation without evidence carries `dataset_id` itself) |
| `validation_failure` | all fields of the validation, plus `seed` (a decimal string), `original_fingerprint`, `minimal_fingerprint`, `shrink_path`, `minimal_input` |
| `calibration` | `implementation`, `dataset_id`, `batch_iterations`, `elapsed_us`, `target_elapsed_us`, `retries` |
| `summary` | `run_id`, `observation_count`, `validation_count`, `calibration_count`, `complete`, `passed_count`, `failed_count`, `unsupported_count`, `expected_difference_count`, `measurement_validation_count`; `environment` with `semantic`, `performance` and `provenance` objects when known; `protocol_identity` and `protocol` (see `protocol_json`) when the protocol is known; `seed` (a decimal string) when the run seed is known |

`status` is one of `valid`, `invalid`, `skipped`, `expected_difference`,
`unsupported`, `infrastructure_failure`; `reason` is the string the status
carries. `phase` is `exploratory` or `confirmatory`; `batch_sink` is `kept`
or `discarded:<reason>`; `setup_timing` is `excluded_from_measurement` or
`included_in_measurement`; `setup_frequency` is `per_run`, `per_dataset`,
`per_implementation`, `per_sample`, `per_batch` or `per_iteration`;
`workspace_scope` is `run_workspace`, `dataset_workspace`,
`implementation_workspace`, `sample_workspace`, `batch_workspace` or
`operation_workspace`. `scale` is the text of the dataset's scale, the same
text the validations of that dataset carry.

The runner fills every field. Fields were added within `mmka_1` over time:
`reason` and `setup_timing`
([issue #8](https://github.com/Luna-Flow/mare_mark/issues/8)), the summary's
`protocol_identity`, `protocol` and `seed`
([issue #3](https://github.com/Luna-Flow/mare_mark/issues/3)), the setup and
measurement-validation fields and `measurement_validation_count`
([issue #4](https://github.com/Luna-Flow/mare_mark/issues/4)), and the
observation's `scale` ([issue #7](https://github.com/Luna-Flow/mare_mark/issues/7)).
Older streams lack them, and readers must not require them.

```moonbit
test "an observation line with its scale and setup" {
  let observation = @model.Observation::new(
    "sum", "loop", "1", 3, 0, 2, Confirmatory, 1.25, 64, Kept, ExcludedFromMeasurement, true,
    setup_frequency=PerDataset, workspace_scope=DatasetWorkspace, scale_text="1024",
  )
  let jsonl = @event.JsonlSink::new()
  (jsonl.as_sink().emit_observation)(observation)
  inspect(jsonl.to_jsonl().contains("\"setup_frequency\":\"per_dataset\""), content="true")
  inspect(jsonl.to_jsonl().contains("\"scale\":\"1024\""), content="true")
}
```
