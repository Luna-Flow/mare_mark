# `runner`

Executable benchmark cases, balanced implementation order, monotonic timed
batches, raw observation emission, and run summaries.

See `doc/<locale>/runner/{api,tutorial,design}.md`. `run_case` performs oracle
validation outside timing, threads sticky contexts, applies fixture lifecycle
policies, calibrates target batch duration, emits separate exploratory and
confirmatory phases, and can isolate unsafe implementations in native
subprocess workers. Implementations may provide a blocking synchronization hook
for queued asynchronous work; JSONL summaries preserve the full execution
environment used for median-based comparisons.
