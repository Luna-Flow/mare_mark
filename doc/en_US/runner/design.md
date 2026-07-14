# `runner` Design

The runner keeps mutation local to prepared inputs and sink accumulation. Each
scale is materialized once, cloned and prepared per implementation, executed in
balanced order, then reset after the complete block.

Timing encloses payload execution and output folding. The clock stops before
`finish` and `Bench::keep`, so final retention cost is excluded. Report
rendering and file IO never enter the measured closure.

Oracle and relational validation execute before timing. `OperationResult`
threads `next_context` across every sequence, while fixture setup/reset follows
the configured lifecycle. Unsafe implementations use native subprocess workers
with hard cancellation, timeout, exit status, stdout, and stderr capture.
Calibration searches between the configured iteration bounds outside the
measurement phase and records elapsed time, target time, and retry count.
Exploratory observations are emitted separately from fixed-budget
confirmatory observations.
