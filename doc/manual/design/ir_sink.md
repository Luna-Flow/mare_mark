# ir_sink design

## Design goal

Give applications one short import for the sinks that feed the report
pipeline, without a second implementation of them.

## Constraints

- It must not define behaviour of its own, so it cannot drift from `event`.
- Its values must mix freely with values built through `event`.

## Mathematical background

Each function of `ir_sink` equals an `event` function:
`in_memory = InMemorySink::new`, `jsonl = JsonlSink::new`,
`jsonl_stream = streaming_jsonl`, `tee = tee`. The package is the identity on
behaviour; it only renames.

## Design decisions

### A facade, not a second sink layer

*Problem.* Examples and applications that only want "events into JSONL for the
report" should not need to learn the full `event` surface. *Choice.* Four
delegating functions. *Why.* Every behaviour is defined once, in `event`, so
the facade cannot drift; the types it returns are the `event` types, so values
from both packages mix freely.

## Correctness and invariants

- Every function returns exactly what the corresponding `event` function
  returns.
- `ir_sink` depends only on `event`.

## Alternatives rejected

- **Re-exporting with `pub using`.** Would also work; named functions keep the
  short names (`jsonl_stream`) independent of `event`'s names.

## Boundaries

- No sink types of its own, no file IO, no parsing.
