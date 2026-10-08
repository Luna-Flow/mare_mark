# model design

## Design goal

Every other package exchanges data through `model`. The package fixes a
vocabulary that is versioned, explicit about failure, and complete enough that
a result can be traced back to its protocol, input and environment. It owns no
behaviour beyond identities and accessors, so it can be depended on by every
layer without cycles.

## Mathematical background

### Environment compatibility as an equivalence relation

Write an environment snapshot as $e = (\sigma, \pi, \rho)$ with semantic part
$\sigma$, performance part $\pi$ and provenance $\rho$. `environment_compatible`
is

$$
e \sim e' \iff (\sigma, \pi) = (\sigma', \pi'),
$$

field by field. This is the kernel of the projection
$p(e) = (\sigma, \pi)$: $e \sim e' \iff p(e) = p(e')$. The kernel of any map is
an equivalence relation, since equality is reflexive, symmetric and transitive.
Hence the snapshots of a set of runs split into classes, and comparisons are
meaningful exactly within a class. Transitivity matters in practice: if run A
may be compared with B and B with C, then A may be compared with C, so a
baseline stored once can serve any later run of the same class.

A relation with tolerances (for example "CPU frequency within 5 %") would not
be transitive and would not split runs into classes; that is why the check is
exact equality of declared strings.

### Outcomes as a sum type

An operation either produces a value or fails in one of several ways that
deserve different treatment. Modelling the result as a sum,

$$
\text{Outcome}(V) = V + V \times \text{Flags} + \text{Trap} \times \text{Flags} + 3 \cdot \text{Reason} + \text{Exit} \times \text{Stderr} + \text{Ms} \times \text{Reason},
$$

keeps the cases apart in types, events and reports. `value_option` is the
projection onto the first two summands; every other summand has no value, and
a timed batch containing one is invalid.

## Design decisions

### Versioned identifiers

*Problem.* Readers of old JSONL must not silently misread new fields.
*Choice.* Three version enums produce the identifiers `mmkp_1` (protocol
vocabulary), `mmka_1` (event artifacts) and `mmks_1` (Plot IR). Every event
carries `artifact_version`; readers reject unknown versions. *Why.* Additive
changes keep the version; a breaking change adds `V2` and a lifecycle entry,
and old readers fail loudly instead of guessing.

### Three-part environment snapshots

*Problem.* Some differences invalidate correctness (target, flags, ABI), some
invalidate timings (CPU, GC, clock, frequency policy), and some are just
bookkeeping (hostname, time, revision). *Choice.* `SemanticEnvironment`,
`PerformanceEnvironment` and `ProvenanceEnvironment`, with compatibility on
the first two. *Why.* Two runs on different hosts with the same declared
hardware remain comparable; a run with different flags does not. The snapshot
records what you declare; mare_mark does not probe the machine.

### Explicit protocols

*Problem.* "Ran the benchmark" hides warmup, batch sizes, order, sample counts
and the decision threshold. *Choice.* `RunProtocol` names all of them, and
`protocol_identity` folds the warmup count, the confirmatory sample count and
the practical threshold into a short key. *Why.* A result is reproducible only
if its protocol is. The key is deliberately short and does not cover every
field; store the full protocol next to results that will be compared.

### Failure kinds instead of strings

`ExecutionOutcome` distinguishes a worker crash (`Aborted`) from a timeout, a
decoding problem, an unsupported input and an accepted deviation, and
`ValidationStatus` mirrors that on the oracle side. Reports count each kind in
the capability matrix, so "unsupported" never reads as "wrong" and a timeout
never reads as a slow measurement.

### Read-only records with constructors

Records are `pub struct`: fields are readable everywhere, values are built
through `new`. Enums that users need to build are `pub(all)`. `IntervalMode`
and `CrossoverResult` are built through functions so that their construction
stays a single, documented path.

### Decision and deployment types

`ScaleBoundary`, `Region`, `ParetoPoint`, `DeploymentPolicy` and
`CrossoverResult` describe how a measured preference becomes a deployment rule.
They live in `model` so that `experiment`, `tune` and applications agree on
them without depending on each other.

## Correctness and invariants

- `environment_compatible` is an equivalence relation (derived above).
- `X::identifier()` is `implementation() + "_" + version()` for every version
  enum, and the `V1` values are `Supported`.
- `ExecutionOutcome::value_option(o)` is `Some` exactly for `Value` and
  `RaisedFlags`; `flags(o)` is non-empty only for `RaisedFlags` and `Trapped`.
- `OperationResult::completed(v, c)` equals
  `OperationResult::new(Value(v), Some(c))` with empty output and no exit code.
- Constructors copy nothing and validate nothing: validation belongs to
  `runner.validate_protocol` and `BenchSpec::compile`.

## Alternatives rejected

- **Probing the environment.** Reading CPU model, governor and GC settings
  needs per-platform code and permissions; declared values are explicit and
  testable.
- **Tolerant compatibility.** Not transitive (see above).
- **Free-form outcome strings.** Lose the distinction between failure kinds.
- **One flat protocol string.** Unreadable and unvalidated.

## Boundaries

- No validation of values; no IO; no serialization (JSON lives in `event`,
  `report` and `tune_gemm`).
- `protocol_identity` covers three fields only.
- `ExperimentDesign`, `ValidationCoverage`, `OutlierPolicy` and
  `WorkspaceScope` are recorded intent; the runner does not interpret them.
- `ProtocolVersion`, `ArtifactVersion` and `SchemaVersion` have one version each;
  there is no migration code.
