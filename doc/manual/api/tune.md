# tune API

`Luna-Flow/mare_mark/tune` provides the policy side of auto-tuning: candidate
spaces, budgets and holdouts, robust scores, selection with a practical
threshold, Pareto fronts, and a seeded candidate order. It does not build or
run candidates; your application measures them (usually with `runner`) and
hands the numbers to these functions. See the [tune design](../design/tune.md).

Source: [`src/tune/tune.mbt`](../../../src/tune/tune.mbt).

```text
import {
  "Luna-Flow/mare_mark/tune",
}
```

## Candidates

### `CandidateSpace`

`CandidateSpace` describes the configurations a tuner may try.

```mbti
pub struct CandidateSpace[Candidate] {
  enumerate : () -> Array[Candidate]
  candidate_id : (Candidate) -> String
  valid : (Candidate) -> Bool
  neighbors : (Candidate) -> Array[Candidate]
}
pub fn[Candidate] CandidateSpace::new(() -> Array[Candidate], (Candidate) -> String, (Candidate) -> Bool, (Candidate) -> Array[Candidate]) -> Self[Candidate]
```

`enumerate` lists the space in a deterministic order, `candidate_id` gives a
unique stable id, `valid` rejects configurations that violate constraints
before they are measured, and `neighbors` lists nearby configurations for a
local search you write yourself (no function in this package uses it).

### `BuiltCandidate`

`BuiltCandidate` pairs a candidate id with the runnable implementation built
for it.

```mbti
pub struct BuiltCandidate[Prepared, Output, Context] {
  candidate_id : String
  implementation : @runner.Implementation[Prepared, Output, Context]
  kernel_id : String
}
pub fn[Prepared, Output, Context] BuiltCandidate::new(String, @runner.Implementation[Prepared, Output, Context], String) -> Self[Prepared, Output, Context]
```

### `BuildEvent`

`BuildEvent` records whether a candidate was accepted and why not.

```mbti
pub struct BuildEvent {
  candidate_id : String
  kernel_id : String
  accepted : Bool
  reason : String
}
```

`reason` is `""` for accepted candidates, `"constraint"` for candidates
rejected by `valid`, and `"measurement"` for candidates whose score is not
usable.

## Budgets and objectives

### `TuningBudget`

`TuningBudget` bounds a tuning run.

```mbti
pub struct TuningBudget[Scale] {
  max_candidates : Int
  max_measurements : Int
  max_elapsed_us : Double?
  exploration_samples : Int
  confirmation_samples : Int
  finalists : Int
  holdout : HoldoutPlan[Scale]
}
pub fn[Scale] TuningBudget::new(Int, Int, Double?, Int, Int, Int, HoldoutPlan[Scale]) -> Self[Scale]
```

The fields describe a two-stage search: explore every candidate with
`exploration_samples`, confirm the best `finalists` with
`confirmation_samples`, and check the winner on the `holdout`. The record is
data for your tuning loop; no function here enforces it.

### `HoldoutPlan`

`HoldoutPlan` names the data kept back to check that a winner generalizes.

```mbti
pub(all) enum HoldoutPlan[Scale] {
  MeasurementHoldout(Int)
  DatasetHoldout(Array[Int])
  ShapeHoldout(Array[Scale])
  WorkloadHoldout(String)
  Combined(Array[HoldoutPlan[Scale]])
}
```

| Constructor | Held back |
| --- | --- |
| `MeasurementHoldout(n)` | the last `n` measurements |
| `DatasetHoldout(ids)` | these datasets |
| `ShapeHoldout(scales)` | these scales or shapes |
| `WorkloadHoldout(name)` | a named workload |
| `Combined(plans)` | all of the above that are listed |

### `TuningObjective`

`TuningObjective` states what "best" means.

```mbti
pub struct TuningObjective {
  practical_delta_pct : Double
  max_workspace_bytes : UInt64?
  minimize_secondary : Bool
}
pub fn TuningObjective::new(Double, UInt64?, Bool) -> Self
```

Candidates within `practical_delta_pct` of the fastest count as tied; ties are
broken by the secondary metric, minimized or maximized.

## Scores

### `CandidateScore`

`CandidateScore` is the measured result of one candidate.

```mbti
pub struct CandidateScore {
  candidate_id : String
  primary : Double
  secondary : Double
  valid : Bool
}
pub fn CandidateScore::new(String, Double, Double, Bool) -> Self
```

`primary` is the cost to minimize (time), `secondary` a tie-breaker (memory,
code size). A score is usable when `valid` is true and both values are finite
and non-negative; the functions below ignore other scores.

### `score_samples`

`score_samples` turns timing samples into a score: the median of the usable
samples.

```mbti
pub fn score_samples(String, Array[Double], Double) -> CandidateScore
```

Samples that are `NaN`, infinite or negative are dropped. If none remain, or
the secondary value is not finite and non-negative, the score has
`valid = false` and `primary = 0.0`.

```moonbit
test "median score" {
  let score = @tune.score_samples("64x64", [9.0, 1.0, 5.0, -1.0, 3.0], 4096.0)
  inspect(score.primary, content="4")
  inspect(score.valid, content="true")
}
```

### `select_best`

`select_best` picks the winner among usable scores.

```mbti
pub fn select_best(Array[CandidateScore], Double, Bool) -> CandidateScore?
```

Arguments: scores, practical threshold $t$ in percent, and whether to minimize
the secondary metric. With $p_{\min}$ the smallest primary, the finalists are
the scores with $100\,(p - p_{\min})/p_{\min} \le t$ (when $p_{\min} = 0$, those
with $p = 0$). Among them it returns the best secondary value, then the
smallest id. A threshold that is `NaN`, infinite or negative is treated as
`0`. Returns `None` when no score is usable. The result does not depend on the
order of the input.

```moonbit
test "fast enough, then small" {
  let scores = [
    @tune.CandidateScore::new("fastest", 100.0, 900.0, true),
    @tune.CandidateScore::new("lean", 103.0, 100.0, true),
    @tune.CandidateScore::new("leaner-but-slow", 110.0, 10.0, true),
  ]
  inspect(@tune.select_best(scores, 5.0, true).unwrap().candidate_id, content="lean")
  inspect(@tune.select_best(scores, 0.0, true).unwrap().candidate_id, content="fastest")
}
```

### `pareto_frontier`

`pareto_frontier` keeps the usable scores that no other usable score
dominates.

```mbti
pub fn pareto_frontier(Array[CandidateScore]) -> Array[CandidateScore]
```

A score $o$ dominates $c$ when $o.p \le c.p$, $o.s \le c.s$ and one of the two
is strict (both metrics are minimized). The result is sorted by primary, then
secondary, then id. Cost: $O(n^2)$.

```moonbit
test "Pareto front" {
  let front = @tune.pareto_frontier([
    @tune.CandidateScore::new("a", 1.0, 9.0, true),
    @tune.CandidateScore::new("b", 2.0, 4.0, true),
    @tune.CandidateScore::new("c", 3.0, 5.0, true),
    @tune.CandidateScore::new("d", 4.0, 1.0, true),
  ])
  debug_inspect(front.map(s => s.candidate_id), content="[\"a\", \"b\", \"d\"]")
}
```

## Search helpers

### `exhaustive_scores`

`exhaustive_scores` scores a prefix of a candidate space and names the fastest
usable candidate.

```mbti
pub fn[Candidate] exhaustive_scores(CandidateSpace[Candidate], Int, (Candidate) -> CandidateScore) -> TuningResult
```

It takes the first $\min(\text{budget}, \lvert\text{space}\rvert)$ candidates
of `enumerate()`. Each valid candidate is scored by the callback; invalid ones
are not. The policy string is `"global:<id>"` of the smallest usable primary
(first one on ties), or `"global:"` when none is usable.

```moonbit
test "exhaustive search" {
  let space = @tune.CandidateSpace::new(
    () => [8, 16, 32, 64],
    n => "block-" + n.to_string(),
    n => n <= 32,
    _ => [],
  )
  let cost = [8.0, 5.0, 6.0, 1.0]
  let result = @tune.exhaustive_scores(space, 10, n => {
    let index = if n == 8 { 0 } else if n == 16 { 1 } else if n == 32 { 2 } else { 3 }
    @tune.CandidateScore::new("block-" + n.to_string(), cost[index], 0.0, true)
  })
  inspect(result.policy, content="global:block-16")
  inspect(result.build_events[3].reason, content="constraint")
}
```

### `TuningResult`

`TuningResult` is the outcome of `exhaustive_scores`.

```mbti
pub struct TuningResult {
  scores : Array[CandidateScore]
  build_events : Array[BuildEvent]
  policy : String
}
```

`scores` holds the scores of valid candidates (usable or not),
`build_events` one event per examined candidate.

### `seeded_order`

`seeded_order` permutes candidates by a seeded hash of their ids.

```mbti
pub fn[Candidate] seeded_order(Array[Candidate], UInt64, (Candidate) -> String) -> Array[Candidate]
```

Each id is hashed with FNV-1a keyed by the seed; candidates are sorted by hash,
then by id. The result depends on the set of ids and the seed, not on the
input order. Use a prefix of it as a reproducible random subset.

```moonbit
test "seeded order is input-order independent" {
  let a = @tune.seeded_order(["x", "y", "z"], 9UL, s => s)
  let b = @tune.seeded_order(["z", "x", "y"], 9UL, s => s)
  inspect(a == b, content="true")
}
```

### `confirmation_count`

`confirmation_count` scales the number of confirmation samples with the
measured uncertainty.

```mbti
pub fn confirmation_count(Int, Double, Int) -> Int
```

`confirmation_count(base, u, budget)` is `base` times 1, 2 or 3 for
$u \le 0.05$, $0.05 < u \le 0.2$ and $u > 0.2$, clamped to $[0, \text{budget}]$.
`u` is a relative uncertainty of your choice, for example IQR divided by
median.

```moonbit
test "more samples when noisy" {
  inspect(@tune.confirmation_count(10, 0.01, 100), content="10")
  inspect(@tune.confirmation_count(10, 0.1, 100), content="20")
  inspect(@tune.confirmation_count(10, 0.5, 25), content="25")
}
```
