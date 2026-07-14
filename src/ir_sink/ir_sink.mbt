///|
pub fn in_memory() -> @event.InMemorySink {
  @event.InMemorySink::new()
}

///|
pub fn jsonl() -> @event.JsonlSink {
  @event.JsonlSink::new()
}

///|
pub fn jsonl_stream(
  write_line : (String) -> Unit,
  location : String,
) -> @event.ObservationSink {
  @event.streaming_jsonl(write_line, location)
}

///|
pub fn tee(
  left : @event.ObservationSink,
  right : @event.ObservationSink,
) -> @event.ObservationSink {
  @event.tee(left, right)
}
