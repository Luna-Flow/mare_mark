# generator design

## Design goal

A benchmark must be rerunnable on the same inputs years later and on another
target. `generator` provides the two primitives this needs: a seed derivation
that turns one run seed into independent, named streams, and a fingerprint
that records which input was actually used. Both are pure functions of their
arguments.

## Constraints

- Derived seeds and fingerprints must be bit-identical on native, JS, wasm and
  wasm-gc, years apart.
- Inputs must depend on their names and ids only, never on the order in which
  they are generated.
- The functions keep no state between calls.

## Mathematical background

All arithmetic is on 64-bit words, modulo $2^{64}$. Write $\oplus$ for
exclusive or and $\gg$ for a logical right shift.

### The derivation

`derive_seed(s, D, i)` with a domain string $D = c_1 c_2 \dots c_m$ (Unicode
code points) and an index $i$ computes

$$
\begin{aligned}
h_0 &= s \oplus \mathtt{0xCBF29CE484222325}, \\
h_j &= (h_{j-1} \oplus c_j)\cdot \mathtt{0x100000001B3}, \qquad j = 1, \dots, m, \\
z_0 &= (h_m \oplus i)\cdot \mathtt{0x9E3779B97F4A7C15}, \\
z_1 &= (z_0 \oplus (z_0 \gg 30))\cdot \mathtt{0xBF58476D1CE4E5B9}, \\
z_2 &= (z_1 \oplus (z_1 \gg 27))\cdot \mathtt{0x94D049BB133111EB}, \\
\mathrm{derive\_seed}(s, D, i) &= z_2 \oplus (z_2 \gg 31).
\end{aligned}
$$

The first two lines are FNV-1a with the 64-bit offset basis and prime, keyed by
the seed; the third multiplies by $\lfloor 2^{64}/\varphi\rfloor$, the golden
ratio increment of SplitMix64; the last three are the SplitMix64 output
finalizer.[^splitmix]

[^splitmix]: G. L. Steele, D. Lea and C. H. Flood, "Fast splittable pseudorandom number generators", OOPSLA 2014. The finalizer constants are those of SplitMix64.

### Injectivity

Each step is a bijection of 64-bit words:

- $x \mapsto x \oplus a$ is its own inverse;
- $x \mapsto a\,x$ with $a$ odd is invertible modulo $2^{64}$, because
  $\gcd(a, 2^{64}) = 1$; all four multipliers (the FNV prime, the golden-ratio
  constant and the two finalizer constants) are odd;
- $x \mapsto x \oplus (x \gg k)$ with $k \ge 1$ is invertible: the top $k$ bits
  are unchanged, and each lower block of $k$ bits is recovered from the block
  above it.

Two consequences follow directly.

1. **Distinct indices never collide.** For fixed $s$ and $D$, $h_m$ is fixed,
   and $i \mapsto z_0 \mapsto z_1 \mapsto z_2 \mapsto$ result is a composition
   of bijections. Two datasets, repetitions or blocks with different ids get
   different seeds, for every run seed.
2. **Distinct run seeds never collide.** For fixed $D$ and $i$, $s \mapsto h_0$
   is a bijection, every FNV step $h \mapsto (h \oplus c)\,p$ is a bijection,
   and so is the rest. Changing the run seed changes every derived seed.

For fixed $s$ and $i$, two domains collide exactly when their FNV states
$h_m$ collide, because everything after $h_m$ is a bijection. Collisions are
therefore possible only between different domains, or between different
(domain, index) pairs with $h_m \oplus i = h'_{m'} \oplus i'$. Modelling FNV-1a
as a random function, $N$ distinct domain strings collide with probability at
most $\binom N2 2^{-64} < N^2/2^{65}$; this is a heuristic, not a property
of FNV-1a. The index enters through `Int::to_uint64`, which sign-extends and
is injective, so negative indices are distinct from non-negative ones.

The finalizer gives avalanche: flipping one input bit flips each output bit
with probability close to $1/2$. Consecutive indices therefore produce
unrelated seeds even though $z_0$ differs between them only in low bits.

### Chained derivation

`measurement_seed(s, d, r, b)` applies `derive_seed` three times with the
domains `"dataset"`, `"repetition"` and `"block"`. By consequence 2 applied to
the outer calls and consequence 1 to each level, changing any one of
$d$, $r$, $b$ with the others fixed changes the result.

### Fingerprints

`stable_fingerprint(x)` is `"sha256:"` followed by the hex digest of
SHA-256 of the UTF-8 bytes of $x$. Collisions require about $2^{128}$ work, so
among $N$ fingerprints an accidental collision has probability at most
$N^2/2^{257}$.

## Design decisions

### Derived streams instead of one global generator

*Problem.* With one random stream, adding a dataset or reordering calls changes
every later input. *Choice.* Every consumer derives its own seed from the run
seed, a domain and an index. *Why.* Inputs depend only on their names and ids,
not on the order of generation, so a subset of datasets can be regenerated
alone and adding a dataset does not change the others.

### Integer mixing instead of a library generator

The derivation uses only multiplication, exclusive or and shifts on 64-bit
integers, which every MoonBit backend implements identically. A float-based or
platform generator could differ between native, JS and wasm.

### Code points, not bytes

The domain is hashed one Unicode code point at a time. For ASCII domains this
is standard FNV-1a; for other characters it differs from FNV-1a over UTF-8
bytes but is still deterministic. Use ASCII domain names if another tool must
reproduce the seeds.

### SHA-256 fingerprints

*Problem.* Inputs must be identified in artifacts without storing them.
*Options.* FNV or another fast non-cryptographic hash; SHA-256. *Choice.*
SHA-256 with an algorithm prefix. *Why.* Fingerprints are compared across
machines and years; a collision would silently merge two inputs. The prefix
leaves room for another algorithm without ambiguity.

### The runner passes the seed through

The runner gives the fixture a `GenerationContext` with the run seed itself.
The fixture decides which domains it needs and derives them, for example
`derive_seed(context.seed, context.case_id, context.dataset_key.dataset_id)`.
Keeping the derivation in the fixture lets one fixture draw several
independent streams.

## Correctness and invariants

- **Determinism and portability.** Results depend only on the arguments and
  are bit-identical on every target.
- **Injectivity** in the index and in the seed, as derived above.
- **Fingerprint format.** Always `sha256:` followed by 64 lowercase hex digits.
- **Purity.** No function keeps state between calls.

## Alternatives rejected

- **A stateful global random generator.** Order-dependent.
- **`seed + index`.** Adjacent seeds would feed correlated streams to
  generators that do not mix their seed.
- **Content hashes with a fast non-cryptographic hash.** Too easy to collide
  for audit purposes.

## Boundaries

- `generator` provides seeds, not random numbers: drawing values is the job of
  your generator function.
- The derivation is not cryptographic: seeds can be predicted from the run
  seed, which is the point.
- `stable_fingerprint` is unkeyed and does not authenticate data.
- Canonical serialization of inputs is up to the caller.
