# tune design

## Design goal

Auto-tuning picks a configuration (block sizes, kernel variant, layout) by
measuring candidates. Done naively it overfits: the "winner" is often the
candidate whose noise happened to be favourable, on the shapes that happened to
be measured. `tune` provides the policy pieces that prevent this, robust
scores, practical ties, confirmation and holdouts, while leaving the building
and running of candidates to the application, where they can be validated and
measured like any other benchmark.

## Mathematical background

### Scores

A candidate $c$ measured $n$ times has samples $t_1, \dots, t_n$. Its score is
the median of the usable samples (finite, non-negative), for the robustness
reasons derived in the [stats design](stats.md). A secondary metric $s_c$
(workspace bytes, code size) breaks ties.

### The winner's curse

Let $\hat p_c = p_c + \varepsilon_c$ be the measured score of candidate $c$
with true cost $p_c$ and zero-mean noise. Choosing the minimum of the
measurements is biased downward:

$$
\mathbb E\bigl[\min_c \hat p_c\bigr] \le \min_c \mathbb E[\hat p_c] = \min_c p_c ,
$$

because $\min_c \hat p_c \le \hat p_{c^*}$ for the truly best $c^*$, and taking
expectations gives $\mathbb E[\min_c \hat p_c] \le p_{c^*}$. With many
candidates of similar cost, the selected one is more likely to be lucky than
good. Two remedies follow, and `TuningBudget` names both: re-measure the
`finalists` with fresh `confirmation_samples` (the new noise is independent of
the selection, so the confirmed score is unbiased), and evaluate the winner on
a `holdout` it was not selected on.

### Practical ties

`select_best` with threshold $t$ forms the tie set

$$
F = \Bigl\{\, c : \frac{p_c - p_{\min}}{p_{\min}} \cdot 100 \le t \,\Bigr\},
$$

and returns the element of $F$ with the best secondary value, then the smallest
id. The rule is order independent: $F$ is defined by values only, and the
second step is the minimum of a total order (secondary, then id) on $F$, which
is unique when ids are unique. So permuting the input cannot change the
result.

### Pareto dominance

With both metrics minimized, $o$ dominates $c$ ($o \prec c$) when
$p_o \le p_c$, $s_o \le s_c$ and $(p_o, s_o) \ne (p_c, s_c)$. The frontier is
$\{c : \nexists\, o \prec c\}$. Sorted by primary cost, the frontier has
strictly decreasing secondary cost: if $p_a < p_b$ and $s_a \le s_b$ then
$a \prec b$, a contradiction, so $s_a > s_b$. Points with equal primary cost on
the frontier must also have equal secondary cost. Every point off the frontier
is dominated by a point on it (dominance is a strict partial order on a finite
set, so every chain ends in a minimal element).

### Random subsets of a large space

`seeded_order` sorts candidates by a seeded 64-bit FNV-1a hash of their ids,
which acts as a pseudo-random permutation. Take its first $B$ candidates. If
the ids are unrelated to quality, every candidate is equally likely to land in
the prefix, and the probability that the prefix contains at least one candidate
from the best fraction $q$ of the space is

$$
1 - (1 - q)^{B} .
$$

$B = 60$ already gives $1 - 0.95^{60} \approx 0.954$ for the top 5 %. This is the
classical argument for random search over grids.[^random]

[^random]: J. Bergstra and Y. Bengio, "Random search for hyper-parameter optimization", *JMLR* 13, 2012.

## Design decisions

### Policy here, effects in the application

*Problem.* Building a candidate may mean compiling a kernel; running it must be
validated and timed under a protocol. *Choice.* `tune` takes scores as input
and never runs anything; `BuiltCandidate` carries a `runner.Implementation`.
*Why.* Tuning measurements then go through the same validation, calibration
and event stream as every other benchmark, and the tuning policy is testable
with made-up numbers.

### Median scores

`score_samples` takes the median of usable samples and marks a candidate with
no usable sample invalid, so a candidate cannot win because a broken
measurement returned `0` or `NaN`.

### Exhaustive search over a bounded prefix

`exhaustive_scores` scores the first `budget` candidates of the enumeration
and records a `BuildEvent` for each, including rejected ones. Combined with
`seeded_order`, the prefix is a reproducible random subset; with the natural
order and a large budget, it is a full grid search. The policy string
`global:<id>` names a single global winner; finer policies (per shape,
Pareto) are built with `select_best`, `pareto_frontier` and
`@model.DeploymentPolicy`.

### Adaptive confirmation

`confirmation_count` multiplies the base confirmation count by 1, 2 or 3 as the
relative uncertainty crosses 5 % and 20 %, clamped to the budget. Noisy
finalists get more samples, quiet ones do not waste time.

## Correctness and invariants

- `select_best` returns `None` exactly when no score is usable; otherwise its
  result is usable, within the threshold of the fastest, and independent of
  input order (derived above).
- `pareto_frontier` returns only usable, non-dominated scores, sorted by
  primary, secondary, id.
- `exhaustive_scores` examines at most `budget` candidates and calls the score
  callback only for valid ones.
- `seeded_order` is a permutation of its input that depends only on the ids and
  the seed.
- `confirmation_count` lies in $[0, \text{budget}]$.

## Alternatives rejected

- **Bayesian optimization or evolutionary search.** Effective, but needs a
  model of the space and makes results harder to reproduce; the hooks
  (`neighbors`, `seeded_order`) allow a user-written search.
- **Mean scores.** One preempted run would decide.
- **Selecting the raw minimum.** Subject to the winner's curse.

## Boundaries

- No candidate is built, run or validated here.
- `TuningBudget`, `TuningObjective` and `HoldoutPlan` are data; no function
  enforces them.
- `CandidateSpace.neighbors` is not used by any function in the package.
- `exhaustive_scores` does not use `seeded_order` itself; reorder the space
  first if you want a random subset.
