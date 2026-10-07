# Package Reference

This page is the maintainer-oriented map of the `0.3.0` public surface. Exact
generic signatures live in each `src/<package>/pkg.generated.mbti`; this page
explains which boundary owns a decision, what is measured, and what must stay
out of a timed region.

## `model`

`model` is the protocol vocabulary shared by every other package. It contains
version identifiers (`mmkp_1`, `mmka_1`, `mmks_1`), dataset and measurement
keys, execution outcomes, environment snapshots, run protocols, observations,
validation events, replay specifications, and tuning/report metadata.

Use `ExecutionOutcome` instead of overloading strings: `Value`,
`RaisedFlags`, `Unsupported`, `ParseFailure`, `Trapped`, `Aborted`, `Timeout`,
and `ExpectedDifference` remain distinguishable in JSONL and reports. Use
`OperationResult` when a stateful operation returns both an outcome and a next
context.

The protocol fields are deliberately explicit:

| Field | Controls |
| --- | --- |
| `ExperimentDesign` | Dataset/repetition structure |
| `CalibrationProtocol` | Target batch time and iteration bounds |
| `SetupPolicy` | Frequency, timing inclusion, and workspace scope |
| `OrderPolicy` | Balanced or fixed implementation order |
| `ValidationCoverage` | Every measurement, dataset, or confirmatory phase |
| `OutlierPolicy` | Report-only, Tukey fence, or MAD trim |

Use `protocol_identity` and `artifact_identity` in cache keys. Environment
compatibility checks semantic and performance fields, but intentionally ignores
run-specific provenance such as hostname, timestamp, revision, and run id.

## `generator`

`generator` owns deterministic input creation. `derive_seed` separates suite,
case, and dataset identities; `measurement_seed` separates repetition and
block identities. `context` creates the immutable `GenerationContext` passed to
the generator, and `stable_fingerprint` records a compact provenance token.

```moonbit nocheck
let seed = @generator.derive_seed(42UL, "vector-add", 3)
let ctx = @generator.context(
  seed, "suite", "vector-add", @model.DatasetKey::new(1024, 3),
  "uniform-int", "1",
)
let input = make_input(ctx)
let fingerprint = @generator.stable_fingerprint(serialize(input))
```

The fingerprint is stable across runs for the same serialized input. It is not
an authentication hash; do not use it to protect untrusted data.

## `fixture`

`fixture` is the lifecycle boundary between generated input and prepared input.
`Fixture::immutable` is the common case where a generated value can be reused;
`Fixture::new` supplies explicit clone, prepare, and reset callbacks.

`SampleContext` identifies a sample and implementation. `ResetContext`
identifies the reset after a measured block. `SetupPolicy` states whether setup
happens per run, dataset, implementation, sample, batch, or iteration and
whether the cost is included in measurement. Keep the policy aligned with the
question being asked: a reusable workspace is a different experiment from
fresh allocation per operation.

## `experiment`

`experiment` supplies validation and shrinking policies. A
`ReferenceOracle` computes an expected sequence from an initial context;
`RelationalOracle` compares implementation pairs; `OracleSpec::ReferenceAndRelational`
composes both without flattening their diagnostics.

`Shrinker` receives candidate inputs and a predicate that must remain true. The
result is the smallest accepted input plus a textual shrink path. Keep the path
in the failure artifact so replay can explain how minimization arrived at the
counterexample.

`ScaleDomain` and `crossover_from_labels` support threshold policies. A
`NonMonotonic` result is not a crossover; callers must not turn it into a
piecewise deployment rule without an explicit policy.

## `runner`

`runner` is the only package that owns the measurement loop. Build a
`BenchSpec`, call `compile`, and pass the resulting `ValidatedBenchPlan` to
`run` with a `RunContext`.

`Implementation::stateless` is convenient for pure payloads;
`Implementation::in_process` carries a context; `Implementation::worker`
executes a native command through `WorkerSpec`, recording timeout, exit code,
stdout, and stderr. Use `synchronize` for asynchronous devices so queued work
is complete at both timing boundaries.

The runtime sequence is:

```text
materialize -> validate/oracle -> prepare -> calibrate -> timed block
           -> fold output -> reset -> emit observation
```

Calibration and validation happen outside timed blocks. Each complete balanced
cycle rotates implementation order using `balanced_order`. Exploratory and
confirmatory observations are emitted as separate phases; summaries should not
mix them accidentally.

`OutputSink::keep_last` is appropriate when the output only needs to stay alive
until the block ends. Use `OutputSink::new` when a checksum, digest, or reduced
state must be retained without timing the final conversion.

## `event` and `ir_sink`

`event` defines `ObservationSink`. `InMemorySink` is useful in tests and local
analysis; `JsonlSink` preserves one-line event records; `streaming_jsonl` emits
each record immediately; `tee` fans out to two sinks. `ir_sink` contains the
named constructors used by applications and examples.

Treat JSONL as an append-only audit stream. Never rewrite raw observations to
apply an outlier policy. A report can discard an invalid point while the event
stream still retains the original reason and artifact.

## `stats`

`summarize` returns count, extrema, mean, median, MAD, quartiles, IQR, and
population standard deviation. `paired_deltas` requires equal-length arrays;
the i-th baseline and candidate values must refer to the same block and
repetition.

`compare_paired` uses median paired delta and a practical threshold. The
bootstrap variant uses an explicit seed, resample count, confidence, and
interval mode. It is a percentile bootstrap, not BCa, studentized, or
hierarchical resampling. Invalid inputs return `BootstrapError` rather than a
plausible-looking interval.

```moonbit nocheck
let result = @stats.compare_paired_with_bootstrap(
  "baseline", "candidate", baseline_us, candidate_us,
  1.0, @model.confirmatory_interval(), 7UL, 2000, 95.0,
).unwrap()
if @stats.is_faster(result) {
  publish("candidate", result.speedup)
}
```

Keep the seed and resample count beside the experiment configuration. Apply
`filter_outliers` only to a derived report view; never mutate the original
paired arrays.

## `ir_model` and `report`

`ir_model` is the portable report vocabulary: `PlotDocument` contains a schema
version, run id, target, plots, and a `DifferentialReport`. Plot kinds distinguish
scaling, raw distribution, block order, intervals, outliers, change points,
heatmaps, and Pareto views. `x` is categorical; a Pareto plot is therefore a
categorical scatter view, not a numeric frontier renderer.

`report.document_from_jsonl` parses the event stream into Plot IR. `plot_json`
is the machine-readable `mmks_1` representation; `plot_svg` renders one plot;
`html` wraps plots, mismatch rows, flags, capabilities, corpus counters, and
counterexamples in a self-contained document. All report functions are pure:
the CLI owns filesystem access.

Invalid observations, discarded batches, and infrastructure failures are
excluded from plotted series. Validation failures remain visible in the
differential section so a fast-but-wrong implementation cannot look like a
speedup.

## `tune`

`tune` provides candidate-space and budget primitives. `CandidateSpace` owns
enumeration, ids, validity, and neighbors. `TuningBudget` separates exploration
from confirmation and names a holdout (`MeasurementHoldout`, `DatasetHoldout`,
`ShapeHoldout`, `WorkloadHoldout`, or `Combined`).

`score_samples` converts paired samples into a primary/secondary score;
`select_best` applies a practical threshold and optional secondary minimization;
`pareto_frontier` retains non-dominated candidates; `seeded_order` makes
candidate evaluation reproducible. `exhaustive_scores` is intentionally a
pure policy helper: applications still own building, running, correctness
validation, and event emission.

## `tune_gemm`

`tune_gemm` is a concrete GEMM policy layer. A `GemmScale` records dimensions,
batch/reuse count, and operand layouts. A `GemmCandidate` records blocking,
microkernel, loop order, packing, allocation mode, and timing scope.

The safe tuning order is:

1. Generate reproducible matrices with `reproducible_matrix`.
2. Reject candidates with `valid_candidate` and workspace limits.
3. Validate numerical output with `gemm_is_correct`.
4. Measure only the configured `TimingScope`.
5. Score candidates with `tune`, preserving holdout shapes.
6. Serialize the exact configuration with `config_json`.

`gemm_reference` is the correctness oracle. `gemm_blocked` is the portable
baseline. `execute_candidate` returns `None` for invalid shapes or buffers; it
does not convert an invalid candidate into a zero-valued result.

## `cli`

The native CLI has two commands:

```sh
mare-mark report events.jsonl report.html
mare-mark report - -
mare-mark replay failure.jsonl --dry-run
mare-mark replay failure.jsonl --yes
```

`report` accepts `-` for stdin/stdout. `replay` currently requires a file
artifact because executing a captured external command is an explicit native
effect. `--dry-run` prints command, arguments, and timeout; execution requires
`--yes`. Unknown options and extra positional arguments are errors.

## Stability Notes

Generated interfaces are authoritative for names and signatures. The following
are intentionally not stable contracts: benchmark timing thresholds, candidate
enumeration order beyond seeded policies, private fixture storage, HTML/CSS
styling, and implementation-specific allocation or algorithm choices.
