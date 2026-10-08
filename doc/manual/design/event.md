# event design

## Design goal

The event stream is the audit record of an experiment: every number in a
report and every replayed failure must be recoverable from it. `event` keeps
that record append-only and line-oriented, and keeps storage choices out of
the runner.

## Constraints

- The record must be streamable, appendable and readable by any tool.
- JSON numbers are doubles, so 64-bit integers cannot be stored as numbers.
- The package does no file IO, so it runs on every target.

## Mathematical background

Model a run as a sequence of events $e_1, e_2, \dots, e_N$ and a sink as a fold
$s_{k} = \text{emit}(s_{k-1}, e_k)$. JSONL serialization is a map $J$ from
events to lines, and the stored stream is the lines $J(e_1), \dots, J(e_N)$
joined by newlines.

Two properties follow from this shape.

1. **Prefix closure.** Every prefix of complete lines is the valid record of
   $e_1, \dots, e_k$. A crash after $k$ events leaves such a prefix (without the
   final summary event, which the runner emits last); a reader that processes
   lines independently can use it.
2. **Projection commutes with concatenation.** A report is built line by
   line, so the projection of two concatenated streams is computed from the
   projections of their lines. Merging or filtering streams is plain text
   processing.

`tee` is the product of two folds: it maps $(s, t)$ to
$(\text{emit}_1(s, e), \text{emit}_2(t, e))$, so a run can be stored in memory
and on disk with one pass.

## Design decisions

### A record of closures

*Problem.* Sinks keep state (arrays, file handles) and are combined (`tee`).
*Options.* A trait with methods; a record of functions. *Choice.* A record of
five closures. *Why.* Closures capture whatever state a sink needs, a record
can be built inline in a test, and combinators like `tee` are ordinary
functions that return a new record.

### One JSON object per line

*Problem.* The record must be streamable, appendable and readable by any tool.
*Choice.* JSONL with a `type` discriminator and an `artifact_version` on every
line. *Why.* A line is self-describing, so readers can skip types they do not
know, grep works, and a crash never corrupts earlier lines. The version on each
line allows streams from different versions to be concatenated and still
rejected precisely.

### Raw values only

Observations carry the per-iteration time of one batch, never a mean, median or
filtered value. Every statistic in a report is recomputed from these raw
values, and an outlier policy cannot rewrite history.

### Seeds as strings

`seed` is written as a decimal string, because a JSON number is a double and
cannot represent every 64-bit integer: integers above $2^{53}$ would be rounded.

### Finish returns a location

`finish` returns where the record went (`memory://run/…`, `jsonl://memory/…`, a
file name), and the runner stores it in the summary. The caller learns where the
evidence is without the runner knowing about files.

## Correctness and invariants

- Each emit call writes exactly one line (`JsonlSink`, `streaming_jsonl`) or
  appends exactly one element (`InMemorySink`).
- Every line carries `artifact_version` `mmka_1` and a `type`.
- `tee` preserves order: for every event, the left sink sees it before the
  right sink.
- `to_jsonl` has one line per event, separated by `\n`.
- Strings are escaped by the JSON encoder, so a line never contains a raw
  newline.

## Alternatives rejected

- **A single JSON document per run.** Not appendable; a crash loses
  everything.
- **CSV.** Nested evidence (operands, flags, environment) does not fit.
- **Binary formats.** Unreadable in review and in issue reports.

## Boundaries

- No file IO: writing lines to disk is the caller's job (the `cli` and
  applications do it).
- `InMemorySink` does not keep the summary.
- The JSONL writer omits the reason strings of validation statuses and the
  observation's `setup_timing`.
- No reader lives here; `report` and `cli` parse the stream.
