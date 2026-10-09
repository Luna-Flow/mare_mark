# event design

## Design goal

The event stream is the audit record of an experiment: every number in a
report and every replayed failure must be recoverable from it. `event` keeps
that record append-only and line-oriented, and keeps storage choices out of
the runner.

## Constraints

- The record must be streamable, appendable and readable by any tool.
- JSON numbers are doubles, so 64-bit integers cannot be stored as numbers,
  and JSON has no `NaN`, no infinities and, in common printers, no `-0`.
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

`seed` (of a failure and of a summary) and the block-order seed in a
protocol are written as decimal strings, because a JSON number is a double and
cannot represent every 64-bit integer: a double has a 53-bit significand, so
above $2^{53}$ only every second integer is representable, above $2^{54}$ only
every fourth, and a seed such as $2^{64} - 1$ would be rounded to $2^{64}$,
which is not even a `UInt64`. Readers accept only the canonical decimal text
(no sign, no leading zeros), so the text round-trips.

### The full protocol in the summary

*Problem.* A record must say how it was measured, and a report must decide
with the threshold and outlier policy the run declared. `protocol_identity`
is a digest and cannot be decoded. *Choice.* The `summary` line carries the
`protocol` object with every field, its `protocol_identity`, and the run
`seed`. `protocol_json` writes the object and `protocol_from_json` reads it.
*Why.* With the object a reader can audit the experiment, re-run it, and
re-analyse it, and the identity next to it lets tools group records without
decoding anything.

The encoding is exact, so that decoding gives back the same protocol and
hence the same identity. Every finite double is written as a JSON number
whose text reads back to the same bits, except that values JSON numbers cannot
hold are strings (`"NaN"`, `"Infinity"`, `"-Infinity"`, as in
`moonbitlang/core/json`) and `-0.0` is written `-0`, because the default text
drops the sign of zero and $0.0$ and $-0.0$ have different identities.
Formally, with $J$ the encoding and $D$ the decoding,

$$
D(J(P)) = P \quad\text{and hence}\quad
\operatorname{protocol\_identity}(D(J(P))) = \operatorname{protocol\_identity}(P)
$$

for every protocol $P$; the tests check it through the JSON text, for every
preset and for edge values (`-0.0`, `1e-300`, `NaN`, both infinities, the
extreme `Int` and `UInt64` values). The decoder ignores unknown keys, so a later version may add fields
within `mmka_1`, and it reads a missing `repeats_per_dataset` as `1`: records
written before the field existed come from runs that measured with one
repetition per dataset.

### Additive fields

`mmka_1` grows by adding fields, never by changing the meaning of one. A new
field is omitted when the producer has nothing to say, so that "not recorded"
looks the same in old and new records: an observation without scale text has
no `scale` key rather than `"scale":""`, and a summary without a protocol has
no `protocol` key. Readers treat a missing key as "not recorded"; `report`,
for example, falls back to `dataset_id` when `scale` is missing and to stated
defaults when `protocol` or `seed` is missing.

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
- The only reader here is `protocol_from_json`, for the `protocol` object;
  `report` and `cli` parse the stream.
