# `runner` Design

The runner keeps mutation local to prepared inputs and sink accumulation. Each
scale is materialized once, cloned and prepared per implementation, executed in
balanced order, then reset after the complete block.

Timing encloses payload execution and output folding. The clock stops before
`finish` and `Bench::keep`, so final retention cost is excluded. Report
rendering and file IO never enter the measured closure.

Every implementation receives the same configured warmup protocol before
calibration. Timed blocks continue one seeded balanced order across exploratory
and confirmatory phases, so each implementation occupies every execution
position once per complete cycle. Repeated raw observations remain available;
robust summaries use their median rather than their mean.

An implementation may provide a blocking `synchronize` hook for asynchronous
devices. The runner invokes it immediately before and after every timed region,
so queued work completes inside the measured boundary. Fixture allocation and
reset follow `SetupTiming`; validation, event emission, final sink conversion,
and report logging remain outside timing.

Oracle and relational validation execute before timing. `OperationResult`
threads `next_context` across every sequence, while fixture setup/reset follows
the configured lifecycle. Unsafe implementations use native subprocess workers
with hard cancellation, timeout, exit status, stdout, and stderr capture.
Calibration searches between the configured iteration bounds outside the
measurement phase and records elapsed time, target time, and retry count.
Exploratory observations are emitted separately from fixed-budget
confirmatory observations.

Run summaries retain the semantic, performance, and provenance environment.
Performance metadata includes CPU, device, concurrency, clock, GC, and frequency
policy; comparisons should reject snapshots for which `environment_compatible`
returns `false`.
