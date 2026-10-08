# event tutorial

This tutorial shows where benchmark events go: into memory for analysis, into
JSONL for the record, to both at once, or into a sink of your own. Every
example is a complete test.

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```text
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/event",
}
```

```moonbit
fn sample_observation(implementation : String, block : Int, elapsed : Double) -> @model.Observation {
  @model.Observation::new(
    "sum", implementation, "1", 0, block, block, Confirmatory, elapsed, 100, Kept, ExcludedFromMeasurement, true,
  )
}

test "keep events in memory" {
  let memory = @event.InMemorySink::new()
  let sink = memory.as_sink()
  (sink.emit_observation)(sample_observation("loop", 0, 3.5))
  (sink.emit_observation)(sample_observation("formula", 0, 0.2))
  inspect(memory.observations.length(), content="2")
  inspect(memory.observations[1].raw_elapsed_us, content="0.2")
}
```

In real use you pass `memory.as_sink()` to `@runner.RunContext::new` and the
runner calls the callbacks.

## Everyday tasks

### Write the audit record

```moonbit
test "JSONL record" {
  let jsonl = @event.JsonlSink::new()
  let sink = jsonl.as_sink()
  (sink.emit_observation)(sample_observation("loop", 0, 3.5))
  let location = (sink.finish)(@model.RunSummary::new("sum-run", 1, 0, 0, true, None))
  inspect(location, content="jsonl://memory/sum-run")
  let lines = jsonl.to_jsonl().split("\n").to_array()
  inspect(lines.length(), content="2")
  inspect(lines[0].contains("\"elapsed_us\":3.5"), content="true")
}
```

Write `jsonl.to_jsonl()` to a file next to the report; the report can always be
regenerated from it.

### Stream while running

For long runs, write each line as soon as it exists:

```moonbit
test "streaming" {
  let file : Array[String] = []
  let sink = @event.streaming_jsonl(line => file.push(line + "\n"), "events.jsonl")
  (sink.emit_observation)(sample_observation("loop", 0, 3.5))
  (sink.emit_observation)(sample_observation("loop", 1, 3.6))
  inspect(file.length(), content="2")
  inspect(file[1].has_suffix("\n"), content="true")
}
```

Replace `file.push` with an append to a real file.

### Keep both

```moonbit
test "tee" {
  let memory = @event.InMemorySink::new()
  let jsonl = @event.JsonlSink::new()
  let sink = @event.tee(memory.as_sink(), jsonl.as_sink())
  (sink.emit_observation)(sample_observation("loop", 0, 3.5))
  inspect(memory.observations.length(), content="1")
  inspect(jsonl.lines.length(), content="1")
  inspect((sink.finish)(@model.RunSummary::new("r", 1, 0, 0, true, None)), content="jsonl://memory/r")
}
```

### Write a sink of your own

A sink that keeps only a running minimum per implementation, for a live
dashboard:

```moonbit
test "a custom sink" {
  let best : Map[String, Double] = Map([])
  let sink = @event.ObservationSink::new(
    observation => {
      if observation.valid {
        let current = best.get(observation.implementation_id).unwrap_or(observation.raw_elapsed_us)
        best[observation.implementation_id] = current.min(observation.raw_elapsed_us)
      }
    },
    _ => (),
    _ => (),
    summary => "dashboard://" + summary.run_id,
  )
  (sink.emit_observation)(sample_observation("loop", 0, 3.5))
  (sink.emit_observation)(sample_observation("loop", 1, 3.1))
  inspect(best.get("loop").unwrap(), content="3.1")
}
```

## Going further

- `@ir_sink` offers the same constructors under shorter names
  (`in_memory`, `jsonl`, `jsonl_stream`, `tee`); see the
  [ir_sink API](../api/ir_sink.md).
- The record format is listed in the [event API](../api/event.md#jsonl-records).

## Common pitfalls

- **Forgetting the failure callback.** `ObservationSink::new` ignores
  validation failures unless you pass `emit_failure=`.
- **Expecting `InMemorySink` to keep the summary.** Use the value returned by
  `run`.
- **Parsing `seed` as a number.** It is a decimal string.

## Next steps

- [event API](../api/event.md), [event design](../design/event.md).
- [report tutorial](report.md) to render a JSONL record.
