# ir_sink tutorial

This short tutorial wires a benchmark's events into both memory and a JSONL
record using the `ir_sink` shorthand.

| I want to | Use |
| --- | --- |
| keep events in memory | `@ir_sink.in_memory()` |
| collect JSONL lines | `@ir_sink.jsonl()` |
| write lines as they are produced | `@ir_sink.jsonl_stream(...)` |
| do both | `@ir_sink.tee(left, right)` |

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.4.0
```

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/ir_sink",
}
```

```moonbit
test "memory and record in one sink" {
  let memory = @ir_sink.in_memory()
  let record = @ir_sink.jsonl()
  let sink = @ir_sink.tee(memory.as_sink(), record.as_sink())
  (sink.emit_validation)(@model.Validation::new(Valid, "reference", "loop", "1024"))
  inspect(memory.validations.length(), content="1")
  inspect(record.to_jsonl().contains("\"status\":\"valid\""), content="true")
}
```

## Everyday tasks

### Stream to a writer

```moonbit
test "stream" {
  let lines : Array[String] = []
  let sink = @ir_sink.jsonl_stream(line => lines.push(line), "stdout")
  (sink.emit_validation)(@model.Validation::new(Unsupported("no NaN support"), "reference", "fast", "8"))
  inspect(lines[0].contains("\"status\":\"unsupported\""), content="true")
}
```

Pass the sink to `@runner.RunContext::new`; the [runner tutorial](runner.md)
shows a complete run.

## Going further

Everything returned here is an `@event` type; see the
[event tutorial](event.md) for custom sinks and the record format.

## Common pitfalls

- **Mixing `ir_sink` and `event` values.** Works, because they are the same
  types; there is nothing to convert.

## Next steps

- [ir_sink API](../api/ir_sink.md), [event API](../api/event.md).
