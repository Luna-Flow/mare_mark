# ir_sink API

`Luna-Flow/mare_mark/ir_sink` is a small facade over [`event`](event.md): four
named constructors for the sinks that applications use most. Each function
calls the `event` function of the same purpose and adds no behaviour.

Source: [`src/ir_sink/ir_sink.mbt`](../../../src/ir_sink/ir_sink.mbt).

```text
import {
  "Luna-Flow/mare_mark/ir_sink",
  "Luna-Flow/mare_mark/model",
}
```

## `in_memory`

`in_memory` returns a new `@event.InMemorySink`.

```mbti
pub fn in_memory() -> @event.InMemorySink
```

## `jsonl`

`jsonl` returns a new `@event.JsonlSink`.

```mbti
pub fn jsonl() -> @event.JsonlSink
```

## `jsonl_stream`

`jsonl_stream` returns `@event.streaming_jsonl(write_line, location)`.

```mbti
pub fn jsonl_stream((String) -> Unit, String) -> @event.ObservationSink
```

## `tee`

`tee` returns `@event.tee(left, right)`.

```mbti
pub fn tee(@event.ObservationSink, @event.ObservationSink) -> @event.ObservationSink
```

```moonbit
test "ir_sink constructors" {
  let memory = @ir_sink.in_memory()
  let record = @ir_sink.jsonl()
  let sink = @ir_sink.tee(memory.as_sink(), record.as_sink())
  inspect((sink.finish)(@model.RunSummary::new("r", 0, 0, 0, true, None)), content="jsonl://memory/r")
  inspect(record.lines.length(), content="1")
}
```
