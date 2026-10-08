# fixture design

## Design goal

The same input must reach every implementation, and the cost of setting it up
must be either inside or outside the measurement by declaration, not by
accident. `fixture` separates the five things that happen to an input
(generate, identify, copy, prepare, reset) so that the runner can place each
of them on the right side of the clock.

## Constraints

- Input, prepared and output types are arbitrary, so the lifecycle is generic
  in them.
- The runner must know on which side of the clock each step falls.
- Fixtures are often written inline in a test, next to the case they serve.

## Mathematical background

A fixture is a small state machine applied per dataset $D$ and implementation
$I$:

$$
\text{ctx} \xrightarrow{\ \text{materialize}\ } x
\xrightarrow{\ \text{clone}\ } x'
\xrightarrow{\ \text{prepare}(\cdot,\, I,\, \text{sample})\ } p
\xrightarrow{\ \text{run}^n\ } p
\xrightarrow{\ \text{reset}\ } \bot .
$$

Two equations express the contract the runner relies on.

1. **Isolation.** If an implementation mutates $p$, the next preparation must
   still see the original $x$: $\text{prepare}(\text{clone}(x))$ must not share
   mutable state with $x$. Then every batch starts from the same state, and the
   measured workload is the same function of $x$ in every block.
2. **Determinism.** $\text{materialize}$ is a function of the context alone, so
   equal contexts give equal inputs and equal fingerprints:
   $\text{ctx} = \text{ctx}' \Rightarrow \text{fingerprint}(\text{materialize}(\text{ctx})) = \text{fingerprint}(\text{materialize}(\text{ctx}'))$.

The runner checks neither; violating them makes blocks measure different
workloads.

### Setup cost in the measurement

Let one operation cost $c$ and one preparation $a$. For a batch of $n$
operations the runner reports $\hat T / n$, where

| `SetupFrequency` | `IncludedInMeasurement` | `ExcludedFromMeasurement` |
| --- | --- | --- |
| `PerIteration` | $c + a$ | $c$ |
| `PerSample`, `PerBatch` | $c + a/n$ | $c$ |
| long-lived | $c$ (the one preparation lands in the first warmup batch, or the first calibration batch without warmup; neither is reported as an observation) | $c$ |

Including setup per batch measures an amortized cost that depends on the batch
size chosen by calibration; include it only per iteration, or when the batch
size is fixed.

## Design decisions

### Closures in a record, not a trait

*Problem.* Fixtures differ in input type, prepared type and policy, and are
often written inline in a test. *Choice.* `Fixture` is a record of functions
with three type parameters. *Why.* A trait would need one type per fixture
and could not carry an id, a version and a policy as values.

### Clone before prepare

The runner always calls `clone_input` before `prepare`. `Fixture::immutable`
makes both the identity, which is free for values that are never mutated; a
mutable input supplies a real copy. Keeping clone and prepare apart lets a
fixture copy the input once and build a workspace around it, and makes the
cost of each visible.

### Implementation-aware preparation

`prepare` receives the implementation id, so it can produce the layout an
implementation expects (packed, transposed, padded). The preparation is then
part of the fixture, and its timing follows the declared policy rather than
hiding inside one implementation's payload.

### Policy as data

`SetupPolicy` is recorded with every observation (`setup_timing`) and in the
event stream. A reader can tell a cold-start measurement from a warm one
without reading code.

## Correctness and invariants

- `materialize` and `fingerprint` run once per dataset.
- `prepare` always receives a fresh `clone_input` result.
- Every short-lived prepared value is reset exactly once; long-lived values are
  reset at the runner's checkpoints and reused (see the
  [runner design](runner.md)).
- `Fixture::immutable` uses identity functions and a no-op reset.

## Alternatives rejected

- **Letting implementations copy their own input.** The copy would be timed
  for some implementations and not for others.
- **One setup hook.** Could not distinguish generation (once per dataset) from
  preparation (per batch or iteration).

## Boundaries

- The fixture does not enforce isolation or determinism; it states the
  contract.
- `WorkspaceScope` is descriptive; the runner keys its cache per
  implementation and dataset.
- `PerRun` and `PerDataset` are prepared per implementation, like
  `PerImplementation`.
- The fixture does not measure memory.
