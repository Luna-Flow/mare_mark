# experiment design

## Design goal

A benchmark compares implementations that are supposed to compute the same
thing. `experiment` states what "the same" means (oracles), makes a failure
small enough to debug (shrinking), and decides when a size-dependent preference
is strong enough to become a deployment rule (crossover analysis). Everything
is a pure function of explicit inputs.

## Constraints

- Correctness is case-specific: tolerances, flags, traps and accepted
  deviations differ between cases.
- One oracle evaluation may run a whole operation sequence, so every search
  over inputs needs a budget.
- A deployment rule must not claim anything about scales that were not
  measured.

## Mathematical background

### Oracles as relations

For an input $x$ and step $k$, a reference oracle defines an expected outcome
$e_k(x)$ and a judgement $V(x, k, e, a) \in \text{ValidationStatus}$ for the
actual outcome $a$. Equality is the special case
$V = \text{Valid} \iff a = e$; floating-point code usually needs a tolerance
$\lvert a - e\rvert \le \epsilon$, and IEEE-aware code compares flags as well.

A relational oracle judges a pair of implementations,
$R(x, k, a^{(i)}, a^{(j)})$. It does not need a reference, but it only detects
disagreement: if all implementations share a bug, the relation holds. The
runner checks all $\binom{m}{2}$ unordered pairs of $m$ implementations; when
the relation is an equivalence (for example exact equality of results), the
pairs are redundant but cheap, and a single deviating implementation shows up
in $m-1$ pairs, which makes it easy to identify.

### Shrinking as greedy descent

Let $C(x)$ be the candidates of $x$ and $P$ the failure predicate. `shrink`
computes

$$
x_0 = x, \qquad x_{j+1} = \text{first } y \in C(x_j) \text{ with } P(y),
$$

and stops when no candidate satisfies $P$ or after `max_steps` evaluations of
$P$.

- **Termination.** Every iteration of the inner loop evaluates $P$ once and
  increments a counter; the outer loop stops when the counter reaches
  `max_steps` or an iteration accepts nothing. At most `max_steps`
  evaluations happen, even when $C$ is cyclic.
- **Invariant.** If $P(x_0)$ holds, then $P(x_j)$ holds for every accepted
  $x_j$, because a candidate is accepted only when $P$ holds for it. The result
  is therefore still a failing input. (`shrink` does not test $x_0$ itself.)
- **Local minimality.** If the loop stops because no candidate fails, the
  result is a local minimum: no element of $C(\text{result})$ satisfies $P$.
  If it stops because of the budget, it may not be.

With $C(n) = [\lfloor n/2\rfloor, n-1]$ and a threshold predicate $P(n) = (n \ge t)$,
the descent halves while it can and then steps down by one, reaching exactly
$t$ in $O(\log n + t)$ accepted steps.

### Crossover detection

Let $s_1 < s_2 < \dots < s_N$ be sorted scales and $\ell_i \in \{A, B, \text{Unknown}\}$
the verdict at $s_i$. The number of transitions is

$$
T = \bigl\lvert\{\, i \in \{2, \dots, N\} : \ell_{i-1} \ne \ell_i,\ \ell_{i-1} \ne \text{Unknown},\ \ell_i \ne \text{Unknown} \,\}\bigr\rvert .
$$

If the relative delta $r(s)$ is monotone in the scale, the labels
$\text{label}(r(s_i))$ form a monotone sequence $A \dots A\, U \dots U\, B \dots B$
(or the reverse), so a well-behaved preference has at most one transition.
$T = 1$ yields the boundary $(s_{i-1}, s_i)$ of the unique transition; $T > 1$
means the preference flips more than once and cannot be expressed as one
threshold; $T = 0$ means no adjacent pair of definite, different labels.

`comparator_label(r, t)` maps the relative delta to the labels with the same
threshold rule as `stats`: $A$ if $r < 0$ and $r \le -t$, $B$ if $r > 0$ and
$r \ge t$, `Unknown` otherwise. The `Unknown` band $(-t, t)$ keeps noise around
$r = 0$ from creating spurious transitions; for $t = 0$ it shrinks to the
single point $r = 0$, so an exact tie never counts as a preference. A
threshold that is `NaN`, infinite or negative has no band at all and yields
`Unknown` for every $r$ (and so $T = 0$); `runner.validate_protocol` rejects
such thresholds before a run.

The labels are counted in scale order. `crossover_from_labels` first sorts the
pairs $(s_i, \ell_i)$ stably with `ScaleDomain.compare`, so the sequence above is
defined by the comparator and not by the order in which the caller listed the
scales. Without the sort, a single crossover measured in the order
$64, 16, 256$ with labels $B, A, B$ would count two transitions.

## Design decisions

### Oracles are values

*Problem.* Each case needs its own notion of correctness. *Choice.* Oracles are
records of functions with an id. *Why.* They can capture tolerances and
contexts, are named in every validation event, and can be built inline.

### Outcomes, not just values, reach the oracle

The oracle sees `ExecutionOutcome`s, so it can accept a documented
`ExpectedDifference`, compare raised flags, or require that both sides trap.
The runner pre-classifies worker crashes, timeouts, decoding errors and
`Unsupported` before the oracle is called, so oracles only judge real results.

### Greedy, first-improvement shrinking

*Options.* Exhaustive search for the smallest failing input; delta debugging;
greedy descent. *Choice.* Greedy descent with an explicit candidate function
and an evaluation budget. *Why.* Each evaluation may run a whole operation
sequence, so the budget is what bounds the cost; the candidate function lets
the user encode the structure of the input (halve a size, drop an element).
The accepted path is recorded so a reader can see how the counterexample was
reached.

### Conservative crossover

*Problem.* A crossover becomes a deployment rule (`DeploymentPolicy::Piecewise`)
that will be applied to inputs never measured. *Choice.* Accept a boundary
only for exactly one transition; report `NonMonotonic` otherwise and leave the
policy to the user. *Why.* A rule built from a noisy, flipping preference
would encode noise.

## Correctness and invariants

- `shrink` evaluates the predicate at most `max_steps` times and returns an
  input satisfying it whenever the initial input does.
- `crossover_from_labels` returns `Found` only when there is exactly one
  transition, and its boundary consists of the two adjacent scales of that
  transition.
- `ReferenceOracle::equal` returns `Valid` only for two `Value` outcomes
  accepted by the comparator.
- For a finite $t \ge 0$, `comparator_label` partitions the real line into
  $(-\infty, -t] \setminus \{0\}$ (`A`), $[t, \infty) \setminus \{0\}$ (`B`)
  and the rest (`Unknown`); for any other $t$ every label is `Unknown`.
- `crossover_from_labels` depends only on the multiset of (scale, label)
  pairs and the comparator, except for the order of pairs whose scales compare
  equal, which the stable sort keeps.

## Alternatives rejected

- **Statistical change-point detection on raw timings.** Needs a noise model;
  labels from practical thresholds are explainable.
- **Interpolating the boundary.** The scales between two measured ones were
  not measured; the result names the two measured scales instead.
- **Delta debugging.** Powerful for sequences, but needs a fixed input
  representation; the candidate function is more general.

## Boundaries

- `crossover_from_labels` uses `ScaleDomain.compare` only to sort; equal
  scales are not merged, and their labels stay in input order.
- A transition across an `Unknown` label (A, Unknown, B) is not counted, so
  such a sequence reports `NoCrossover`.
- Oracles are not run here; the runner runs them. For each input selected for
  reference validation, the runner evaluates `ReferenceOracle.sequence_length`
  once, before running any operation on that input. The result must be
  positive and equal the case's configured sequence length; otherwise the run
  raises `RunConfigError` at that dataset, after earlier datasets have already
  been measured. This equality is a correctness precondition: checking only
  the common prefix would leave a suffix without a verdict. If an expected or
  actual operation sequence terminates early and every common step passed, the
  runner emits an `Invalid` validation and a `ValidationFailure` for the length
  mismatch; a sequence that stopped on a step that did not pass is reported by
  that step only.
- `shrink` does not check that the initial input fails.
