# runner design

## Design goal

A benchmark result is evidence only if three things hold: the implementations
computed the right answer on the measured input, every implementation was
measured under the same conditions, and the measurement can be traced back to a
seed, a protocol and an environment. `runner` is the one package that executes
payloads, and it is built so that these properties hold by construction rather
than by discipline: validation precedes timing, the order of implementations is
balanced, batch sizes are calibrated, and every raw observation is emitted.

## Constraints

- It is the only package that executes payloads, and payloads may be wrong,
  slow, crash or loop.
- Timers have a finite resolution (`performance.now()` may be coarsened to
  100 µs or more in browsers), and machines drift during a run.
- `run` is asynchronous and must work wherever `moonbitlang/async` has a
  runtime; subprocesses exist only on native.
- No event may be emitted inside a timed region.

## Mathematical background

### Blocks and the measurement model

For one dataset the runner measures $k$ implementations in blocks
$b = 0, 1, \dots, E + C - 1$: $E$ exploratory blocks followed by $C$
confirmatory blocks (`exploratory_samples` and `confirmatory_samples`). Inside
a block every implementation runs one batch. Model the per-iteration time of
implementation $i$ in block $b$ as

$$
y_{i,b} = \mu_i + \tau_{p_i(b)} + \delta\, s_i(b) + \varepsilon_{i,b},
$$

where $p_i(b) \in \{0, \dots, k-1\}$ is the position of $i$ inside the block,
$\tau_p$ a position effect (the first batch of a block runs with colder
caches), $s_i(b) = bk + p_i(b)$ the global slot number, $\delta$ a linear drift
(thermal throttling, background load) and $\varepsilon$ noise. The quantity of
interest is $\mu_j - \mu_i$.

### Cyclic Latin square order

Under `OrderPolicy::BalancedBlocks(order_seed)` block $b$ runs the
implementations in the order `balanced_order(k, b + o)`, that is
implementation $(p + b + o) \bmod k$ at position $p$, with offset
$o = (\text{order\_seed} \oplus \text{run\_seed}) \bmod k$. Implementation $i$
therefore sits at position

$$
p_i(b) = (i - b - o) \bmod k .
$$

**Balance.** For fixed $i$, the map $b \mapsto (i - b - o) \bmod k$ is a
bijection from any $k$ consecutive integers onto $\{0, \dots, k-1\}$. Over every
complete cycle of $k$ consecutive blocks each implementation occupies each
position exactly once: the $k \times k$ table of positions is a Latin square.

**Cancellation.** Sum the model over a complete cycle $b_0, \dots, b_0 + k - 1$:

$$
\begin{aligned}
\sum_{b} \tau_{p_i(b)} &= \sum_{p=0}^{k-1} \tau_p, \\
\sum_{b} s_i(b) &= k \sum_{b} b + \sum_{b} p_i(b) = k \sum_{b} b + \frac{k(k-1)}{2}.
\end{aligned}
$$

Both right-hand sides are independent of $i$. The cycle means therefore satisfy

$$
\bar y_j - \bar y_i = \mu_j - \mu_i + (\bar\varepsilon_j - \bar\varepsilon_i),
$$

free of position effects and of linear drift. With `FixedOrder`,
$p_i(b) = i$ in every block and the difference carries the bias
$\tau_j - \tau_i + \delta (j - i)$ for ever.

The cancellation is exact for means over complete cycles; choose $E + C$ as a
multiple of $k$ so that the confirmatory phase, which continues the rotation at
block $E$, covers complete cycles. Medians of paired deltas are robust rather
than exactly unbiased: the per-block bias
$\tau_{p_j(b)} - \tau_{p_i(b)} + \delta (p_j(b) - p_i(b))$ takes each of its $k$
values equally often, and for $k = 2$ it alternates between $+c$ and $-c$.

### Batch calibration

A timer has a resolution $\rho$ and a start/stop overhead $\omega$. A batch of
$n$ iterations that truly takes $T(n)$ is read as
$\hat T = T(n) + \omega + q$ with $\lvert q\rvert \le \rho$, and the runner reports
$\hat T / n$. The relative error of the per-iteration time is at most

$$
\frac{\omega + \rho}{T(n)} ,
$$

which shrinks as the batch grows. Calibration chooses $n$ so that $T(n)$
reaches `target_batch_time_us` $= t$. Starting from
$n_0 = \min(\max(\text{min\_batch\_iterations}, 1), n_{\max})$ with
$n_{\max} = \max(\text{max\_batch\_iterations}, 1)$,
while the batch is valid, $T(n) < t$, $T(n) <$ `max_sample_time_us` and
$n <$ `max_batch_iterations`, the next size is

$$
n_{j+1} = \min\Bigl(n_{\max},\ \max\Bigl(n_j + 1,\ \Bigl\lceil \frac{n_j\, t}{T(n_j)} \Bigr\rceil\Bigr)\Bigr),
$$

with $10\, n_j$ in place of the ratio when the measured time is $0$.

*Linear cost.* If $T(n) = c\,n$, the first update gives
$n_1 = \lceil t / c\rceil$ and $T(n_1) \in [t, t + c)$: one retry suffices.

*Affine cost.* If $T(n) = a + c\,n$ with a fixed per-batch cost $a > 0$, the
update is the fixed-point iteration of $f(n) = n t / (a + c n)$. Its fixed point
solves $a + c n^* = t$, so $n^* = (t - a)/c$, and

$$
f'(n) = \frac{a\, t}{(a + c n)^2}, \qquad f'(n^*) = \frac{a}{t} < 1 .
$$

The iteration contracts with rate $a/t$ near $n^*$. In fact the gap obeys an
exact identity: for $n < n^*$,

$$
\begin{aligned}
n^* - f(n) &= \frac{t - a}{c} - \frac{n t}{a + c n}
= \frac{(t - a)(a + c n) - c n t}{c\,(a + c n)} \\
&= \frac{a\,(t - a - c n)}{c\,(a + c n)}
= \frac{a}{T(n)}\,\bigl(n^* - n\bigr).
\end{aligned}
$$

Since $0 < a < T(n) < t$ while the loop runs, $n < f(n) < n^*$: the iteration
approaches $n^*$ from below without overshooting (up to the rounding by
$\lceil\cdot\rceil$), and each retry multiplies the remaining gap by
$a/T(n_j)$. That factor is close to $1$ while the fixed cost dominates a small
batch, and falls to $a/t$ as $T(n_j)$ approaches the target: when the fixed
cost is 10 % of the target, the last retries reduce the gap about tenfold each.
If $a \ge t$ there is no fixed point, and the batch grows until
`max_batch_iterations` or `max_sample_time_us` stops it. Because every step
increases $n$ by at least one and $n$ is capped by
$n_{\max} = \max(\text{max\_batch\_iterations}, 1)$, the loop terminates
after at most $n_{\max} - n_0$ retries.

With the `QuickCheck` preset ($t = 1000$ µs) and a 1 µs timer, the quantization
error $\rho / T(n)$ of a batch that reached the target is at most $0.1\,\%$; a
batch stopped early by `max_batch_iterations` or `max_sample_time_us` can be
shorter, and its `CalibrationEvent` shows it. In the browser,
`performance.now()` may be coarsened to 100 µs or more; raise the target
accordingly.

## Design decisions

### Validate before timing

*Problem.* A fast wrong answer must not look like a speedup. *Options.*
Validate inside the timed loop; validate afterwards; validate before.
*Choice.* For every dataset the runner first runs a validation sequence of
`sequence_length` operations per implementation, from a fresh
`clone_input`/`prepare` and `initial_context`, and compares it with the oracle.
Timing starts only afterwards. *Why.* Validation inside timing would be timed;
validation afterwards could not show the failing input next to the
measurement. The sequence threads `next_context` from step to step, so stateful
operations (an accumulator, a rounding mode, a parser state) are validated in
the same order in which they are measured.

Before calling the oracle, the runner maps execution outcomes that are not
values:

| Outcome of the implementation | Validation status |
| --- | --- |
| `Unsupported(reason)` | `Unsupported(reason)` |
| `ParseFailure`, `Aborted`, `Timeout` | `InfrastructureFailure(...)` |
| `ExpectedDifference(reason)` | `ExpectedDifference(reason)` |
| `Value`, `RaisedFlags`, `Trapped` | decided by the oracle |

For a relational oracle every unordered pair $i < j$ of implementations is
compared step by step; the event is attributed to the second implementation of
the pair. A sequence that ends early (`next_context = None`) is compared on
the steps both sides produced. `Invalid` and `InfrastructureFailure` count as
failures; a failure triggers the shrinker, if one is configured, and emits a
`ValidationFailure` with the seed, both fingerprints, the shrink path and the
minimal input.

A failure does not stop the measurement. The report removes the series of the
failing implementation for that dataset and shows the mismatch instead.

### Balanced, seeded rotation instead of randomization

*Problem.* Position and drift effects bias a fixed order. *Options.* Fixed
order; an independent random permutation per block; a cyclic Latin square.
*Choice.* The cyclic rotation derived above, with a seeded offset. *Why.* A
random permutation balances positions only in expectation; with ten blocks and
three implementations, one implementation can easily run first four times. The
rotation balances them exactly over every cycle, and the seed still decides
which implementation starts.

### Calibrated batches, and one size per implementation by default

*Problem.* Single operations are too short to time. *Choice.* Every
implementation is calibrated separately (`BatchPolicy::PerImplementation`), so
each reaches the target duration. `BatchPolicy::SharedBatchSize` replaces all
sizes with their minimum, $n = \min_i n_i$, for experiments in which the amount
of work per batch must be identical, at the cost of a shorter batch, and a
larger relative timer error, for the slower implementations. The per-iteration
value $\hat T / n$ is a batch mean: a batch reduces the variance of independent
per-iteration noise by a factor $n$ but also hides the tail inside the batch.

### Explicit timing boundaries

The clock is `@bench.monotonic_clock_start`/`monotonic_clock_end` (µs). What it
encloses depends on the fixture's `SetupPolicy`:

| Setup | `ExcludedFromMeasurement` | `IncludedInMeasurement` |
| --- | --- | --- |
| `PerRun`, `PerDataset`, `PerImplementation` | prepare once and cache; per batch: start, $n \times$ (execute, fold), stop | as excluded, except that the one-time prepare falls inside the timed region of the first batch that runs (usually a warmup batch) |
| `PerSample`, `PerBatch` | prepare; start; $n \times$ (execute, fold); stop; reset | start; prepare; $n \times$ (execute, fold); reset; stop |
| `PerIteration` | $n \times$ (prepare; start; execute; fold; stop; reset), times summed | start; $n \times$ (prepare; execute; fold; reset); stop |

`prepare` here includes `clone_input`. `synchronize` is called immediately
before every start and before every stop. `finish` of the output sink and
`@bench.Bench::keep` run after the stop, outside timing; `keep` stops the
compiler from removing work whose result is unused. Event emission never
happens inside a timed region.

`PerIteration` with excluded setup has a cost: it takes $n$ timer readings per
batch, so the quantization error is
$n\rho / (n c) = \rho / c$ and does not shrink with the batch size. Use it only
for operations that are long compared with the timer resolution.

### Fixture lifecycle and sentinel sample ids

The fixture's `prepare` and `reset` receive a `SampleContext` or
`ResetContext` whose `sample_id` tells the fixture what the runner is doing:

| `sample_id` | Phase |
| --- | --- |
| `-1` | validation sequence |
| `-1000 - w` | warmup batch $w$ |
| `-3` | reset after warmup (long-lived setups only) |
| `-2 - r` | calibration batch after $r$ retries; `-2` is also the reset after calibration |
| `-100000 - r` | exploratory block $r$ |
| `r` | confirmatory block $r$ |
| `confirmatory_samples` | final reset of a cached prepared value |

Long-lived setups (`PerRun`, `PerDataset`, `PerImplementation`) are prepared
once per implementation and dataset, reset after warmup and after calibration,
and reset again at the end of the dataset. The runner keeps one cache per
implementation, so `PerRun` and `PerDataset` currently behave like
`PerImplementation`.

### Warmup

Every implementation runs single-iteration batches until it has run
`warmup_iterations` batches and spent `warmup_time_us`, capped at
$\max(\text{warmup\_iterations}, \text{max\_batch\_iterations})$ batches. The
same warmup applies to every implementation, so none starts the measurement
with an advantage from just-in-time compilation or caches.

### Crash isolation through subprocess workers

*Problem.* A candidate that segfaults or loops forever would end the
experiment. *Choice.* `Implementation::worker` runs each operation as a child
process inside a task group with a hard-cancel handler, captures stdout and
stderr concurrently, and turns a timeout or non-zero exit into an outcome.
*Why.* An outcome is data: it is counted, reported and replayable. Process
creation is part of the measured operation for workers, which is acceptable
for correctness corpora and unsafe code, not for micro-benchmarks.

### Seeds and identities

The run seed reaches the fixture unchanged in
`GenerationContext(seed, "default", case_id, DatasetKey(scale, index), fixture.id, fixture.version)`.
Derive per-dataset seeds from it with `@generator.derive_seed`; the
[generator design](generator.md) explains the mixing. The same seed sets the
rotation offset. Together with the protocol, the plan and the environment
snapshot, the seed determines everything except the timings.

## Correctness and invariants

- **Validation precedes timing** for every dataset and implementation.
- **Balance.** Over every $k$ consecutive blocks each implementation occupies
  each position once (proved above).
- **Event order per dataset.** Validations and failures, then one calibration
  event per implementation, then $k(E + C)$ observations (exploratory first);
  the summary is emitted once, after the last dataset.
- **Counts.** `observation_count` $= \lvert\text{scales}\rvert\cdot k (E + C)$;
  `calibration_count` $= \lvert\text{scales}\rvert \cdot k$;
  `validation_count` is the number of compared steps.
- **Validity.** An observation is `valid = false` when an operation in its batch
  produced no value or ended the context sequence.
- **Termination.** Calibration performs at most $n_{\max} - n_0$ retries; warmup
  at most $\max(\text{warmup\_iterations}, n_{\max})$ batches; shrinking at most
  `max_steps` candidate evaluations.
- **Reset discipline.** A short-lived prepared value (validation sequence,
  `PerSample`, `PerBatch`, `PerIteration`) is reset exactly once. A cached
  long-lived value is reset after warmup, after calibration and at the end of
  the dataset, and reused in between, so `reset` must leave it reusable.

## Alternatives rejected

- **Random permutation per block.** Balanced only in expectation.
- **Williams designs.** They also balance first-order carryover (which
  implementation ran just before), but need $2k$ blocks per cycle for odd $k$.
  The cyclic order always places implementation $i - 1$ before $i$ inside a
  block.
- **Timing each iteration.** Timer overhead and resolution dominate short
  operations; batches amortize them.
- **Stopping when an interval is narrow enough.** Sequential stopping rules
  invalidate fixed-sample intervals; the sample counts are fixed by the
  protocol.
- **Validation after timing.** It would separate a wrong result from the
  measurement that should be discarded.

## Boundaries

- The runner does not pin threads, fix CPU frequency or isolate the process;
  it records what you declare about them in the `EnvironmentSnapshot`.
- `experiment_design`, `outlier_policy`, `validation_coverage` and
  `practical_delta_pct` are stored in the protocol but do not change the run.
  Validation runs once per dataset, before timing, whatever the coverage says.
- It does not compute comparisons or decisions; `stats` does.
- It materializes one input per scale; it does not regenerate inputs per block.
- `protocol_identity`, and hence `run_id`, covers only the warmup count, the
  confirmatory sample count and the practical threshold.
- `validate_protocol` does not reject `NaN` durations or a `NaN` threshold: a
  `NaN` target disables calibration and a `NaN` warmup time disables the time
  criterion of the warmup.
- Subprocess workers need the native target; `run` itself needs an async
  runtime (native, JS or wasm, not wasm-gc).
- First-order carryover between implementations is not balanced.
