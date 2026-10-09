# model design

## Design goal

Every other package exchanges data through `model`. The package fixes a
vocabulary that is versioned, explicit about failure, and complete enough that
a result can be traced back to its protocol, input and environment. It owns no
behaviour beyond identities and accessors, so it can be depended on by every
layer without cycles.

## Constraints

- Every other package depends on `model`, directly or indirectly, so it can
  depend on nothing.
- Records travel through JSONL artifacts that outlive the code that wrote
  them; their meaning must be pinned by a version.
- Values are read everywhere but should be built through one documented path.
- The package has no IO and no behaviour beyond identities and accessors.

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

### Protocol identity: an injective encoding and a digest

`protocol_identity` must change whenever any protocol field changes. It is
built in two steps.

**The encoding is injective.** `protocol_canonical_encoding` writes the
fields in a fixed order as `mmkp_2;k_1=v_1;…;k_{15}=v_{15}`. The keys are
constants, and no value contains `;` or `=`: integers are decimal, doubles are
`0x` plus the 16 hexadecimal digits of their bit pattern, options are `none`
or `some(…)`, enums are snake_case tags, and the block order is `fixed_order`
or `balanced_blocks(<decimal>)`. Splitting the text on `;` and every part at
its first `=` therefore recovers each $(k_i, v_i)$, and each $v_i$ determines
its field (the bit pattern determines the double, a decimal its integer, a
tag its enum value). So

$$
\operatorname{enc}(P) = \operatorname{enc}(P') \iff P = P'
$$

field by field, with doubles compared by bit pattern. Comparing bit patterns
instead of values is deliberate: `0.0` and `-0.0` are equal as numbers but are
different protocols to write down, and a `NaN` threshold, which
`validate_protocol` rejects anyway, still has a well-defined encoding.
Formatting doubles in decimal would make the text depend on a printing
algorithm; the bit pattern is the same on every target.

**The digest is FNV-1a.** With the code units $c_1, \dots, c_n$ of the
encoding (all ASCII),

$$
h_0 = \texttt{cbf29ce484222325}_{16}, \qquad
h_i = (h_{i-1} \oplus c_i) \cdot \texttt{100000001b3}_{16} \bmod 2^{64},
$$

and the identity is `mmkp_2:` followed by $h_n$ in 16 lowercase hexadecimal
digits. Each step $f_c(h) = (h \oplus c)\,p \bmod 2^{64}$ is a bijection of
the 64-bit words, because xor with a constant is its own inverse and the prime
$p$ is odd, hence invertible modulo $2^{64}$. Consequently two encodings
$u\,a\,w$ and $u\,b\,w$ that differ in a single character $a \ne b$ always get
different digests: after $u$ both states equal some $s$, $f_a(s) \ne f_b(s)$,
and the common suffix $w$ applies the same bijections to both. Changing one
digit of one field, the most common edit, can therefore never collide. For
arbitrary different protocols FNV-1a gives no guarantee; treating it as a
random function, $N$ distinct protocols collide with probability at most
$\binom{N}{2} 2^{-64}$, about $3 \cdot 10^{-14}$ for a thousand protocols.
FNV-1a is not collision-resistant against an adversary, so the identity
groups honest results and is not a security token.

### Run identity: recoverable components

`run_identity` joins five components with `|`: the case id, the protocol
identity, the decimal seed, the provenance run id and the provenance
timestamp. The free-text components pass through the escape map $\epsilon$
that replaces `%` by `%25` and then `|` by `%7C`. Its output contains no `|`,
and neither do the protocol identity and the decimal seed, so splitting a run
id on `|` gives exactly five parts. $\epsilon$ is injective: replacing `%7C`
by `|` and then `%25` by `%` inverts it, because every `%` in the output
starts one of the two escapes, so `%7C` matches only escaped bars. Hence two
run ids are equal exactly when all five components are equal, and runs that
differ in seed, provenance run id or timestamp never share an id.

## Design decisions

### Versioned identifiers

*Problem.* Readers of old JSONL must not silently misread new fields.
*Choice.* Three version enums produce the identifiers `mmkp_<n>` (protocol
identity), `mmka_1` (event artifacts) and `mmks_2` (Plot IR). Every event
carries `artifact_version`; readers reject unknown versions. *Why.* Additive
changes keep the version; a breaking change adds a version and a lifecycle
entry, and old readers fail loudly instead of guessing. The protocol identity
went through exactly that: `mmkp_1:<w>:<c>:<d>` covered only the warmup count,
the confirmatory sample count and the threshold, so different protocols
shared a key. `ProtocolVersion::V2` (`mmkp_2`) covers every field, and `V1` is
`Deprecated`: it names old keys and is no longer produced. A key states its
version, so an `mmkp_1` key can never be mistaken for an `mmkp_2` one.

### Three-part environment snapshots

*Problem.* Some differences invalidate correctness (target, flags, ABI), some
invalidate timings (CPU, GC, clock, frequency policy), and some are just
bookkeeping (hostname, time, revision). *Choice.* `SemanticEnvironment`,
`PerformanceEnvironment` and `ProvenanceEnvironment`, with compatibility on
the first two. *Why.* Two runs on different hosts with the same declared
hardware remain comparable; a run with different flags does not. `model`
itself does not probe the machine: a snapshot is a value, built by hand or by
the separate [`env_detect`](env_detect.md) package, which fills it from the
running process and lists what it could not observe. Keeping the probe out of
`model` keeps the vocabulary free of IO and lets tests build exact snapshots.

### Explicit protocols

*Problem.* "Ran the benchmark" hides the experimental design, warmup, batch
sizes, order, sample counts, validation coverage and the decision threshold.
*Choice.* `RunProtocol` names all of them, `protocol_canonical_encoding`
writes every field, and `protocol_identity` digests that text into a short
key (derived above). The runner stores the full protocol and the seed in the
`RunSummary`, and the JSONL summary carries both. *Why.* A result is
reproducible only if its protocol is, and a key that ignores a field lets two
different experiments look like one. A digest keeps the key short enough for
file names and tables while the record keeps the fields themselves.

### Run ids that name one execution

*Problem.* A run id built from the protocol and the case alone is the same
for every repetition of a nightly job. *Choice.* `run_identity` adds the run
seed and the provenance run id and timestamp, escaped so that the parts stay
recoverable (derived above). *Why.* The id then distinguishes executions, and
a reader can still see from the id which case and protocol a run used.

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
  enum. `ProtocolVersion::V1` is `Deprecated`; `ProtocolVersion::V2`,
  `ArtifactVersion::V1` and `SchemaVersion::V1` are `Supported`.
- `protocol_canonical_encoding` is injective and `protocol_identity` changes
  under every single-character change of the encoding (derived above).
- `run_identity` splits into exactly five components on `|`.
- `ExecutionOutcome::value_option(o)` is `Some` exactly for `Value` and
  `RaisedFlags`; `flags(o)` is non-empty only for `RaisedFlags` and `Trapped`.
- `OperationResult::completed(v, c)` equals
  `OperationResult::new(Value(v), Some(c))` with empty output and no exit code.
- Constructors copy nothing and validate nothing: validation belongs to
  `runner.validate_protocol` and `BenchSpec::compile`.

## Alternatives rejected

- **Probing the environment in `model`.** Needs per-platform code, processes
  and permissions; it lives in `env_detect`, and `model` takes the result as a
  value.
- **A cryptographic hash for the protocol identity.** SHA-256 would add a
  dependency to a package that has none, for a key that only needs to
  separate honest protocols; the injective encoding is the actual record.
- **Decimal text for doubles in the encoding.** Depends on a printing
  algorithm and hides the sign of zero.
- **Tolerant compatibility.** Not transitive (see above).
- **Free-form outcome strings.** Lose the distinction between failure kinds.
- **One flat protocol string.** Unreadable and unvalidated.

## Boundaries

- No validation of values; no IO; no JSON (it lives in `event`, `report` and
  `tune_gemm`).
- `protocol_identity` is a 64-bit digest: it separates protocols, it cannot be
  decoded, and it is not collision-resistant against deliberate attempts.
- `WorkspaceScope` is recorded, not interpreted. `OutlierPolicy` and
  `practical_delta_pct` are analysis settings: the runner records them and the
  report applies them.
- There is no migration code: an `mmkp_1` key cannot be converted to `mmkp_2`,
  because it lacks the fields the new key covers.
