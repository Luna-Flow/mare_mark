# experiment API

## Purpose

`Luna-Flow/mare_mark/experiment` holds the correctness side of a benchmark:
reference and relational oracles, input shrinking, and the crossover analysis
that turns per-scale verdicts into a scale boundary. The runner uses the
oracles and shrinkers; you can also call them directly. See the
[experiment design](../design/experiment.md).

Source: [`src/experiment/experiment.mbt`](../../../src/experiment/experiment.mbt).

## Importing

Add the packages to the `moon.pkg` of the package that uses them:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/experiment",
}
```

The examples on this page call them through their default aliases (`@model`,
`@experiment`).

## Oracles

### `ReferenceOracle`

`ReferenceOracle` computes the expected result of every step and judges an
implementation's outcome against it.

```mbti
pub struct ReferenceOracle[Input, Expected, Output, Context] {
  id : String
  initial_context : () -> Context
  sequence_length : (Input) -> Int
  compute_expected : (Input, Int, Context) -> @model.OperationResult[Expected, Context]
  validate : (Input, Int, @model.ExecutionOutcome[Expected], @model.ExecutionOutcome[Output]) -> @model.ValidationStatus
  expected_text : (Expected) -> String
}
pub fn[Input, Expected, Output, Context] ReferenceOracle::new(String, () -> Context, (Input) -> Int, (Input, Int, Context) -> @model.OperationResult[Expected, Context], (Input, Int, @model.ExecutionOutcome[Expected], @model.ExecutionOutcome[Output]) -> @model.ValidationStatus, (Expected) -> String) -> Self[Input, Expected, Output, Context]
```

`compute_expected(input, step, context)` returns the expected outcome of step
`step` and the oracle's next context; the sequence stops when it returns no
context. `validate(input, step, expected, actual)` returns the verdict.
`expected_text` renders expected values in evidence. The runner uses the
case's `sequence_length`, not the oracle's `sequence_length` function.

### `ReferenceOracle::equal`

`ReferenceOracle::equal` builds a one-step oracle from a reference function and
an equality.

```mbti
pub fn[Input, Expected, Output] ReferenceOracle::equal(String, (Input) -> Expected, (Expected, Output) -> Bool) -> Self[Input, Expected, Output, Unit]
```

The verdict is `Valid` when both outcomes are `Value` and the comparator
accepts them, `Invalid("value mismatch")` when the comparator rejects them, and
`Invalid("outcome mismatch")` for any other pair of outcomes. Expected values
are rendered as `"<expected>"`.

```moonbit
test "an equality oracle with a tolerance" {
  let oracle = @experiment.ReferenceOracle::equal(
    "sqrt",
    (x : Double) => x.sqrt(),
    (expected : Double, actual : Double) => (expected - actual).abs() <= 1.0e-12,
  )
  let ok = @experiment.validate_reference(oracle, 2.0, 0, Value(2.0.sqrt()), Value(1.4142135623731), "fast", "2")
  let bad = @experiment.validate_reference(oracle, 2.0, 0, Value(2.0.sqrt()), Value(1.5), "fast", "2")
  inspect(ok.status is Valid, content="true")
  inspect(bad.status is Invalid("value mismatch"), content="true")
}
```

### `validate_reference`

`validate_reference` applies a reference oracle to one step and wraps the
verdict in a `Validation` without evidence.

```mbti
pub fn[Input, Expected, Output, Context] validate_reference(ReferenceOracle[Input, Expected, Output, Context], Input, Int, @model.ExecutionOutcome[Expected], @model.ExecutionOutcome[Output], String, String) -> @model.Validation
```

Arguments: oracle, input, step, expected outcome, actual outcome,
implementation id, scale text.

### `RelationalOracle`

`RelationalOracle` judges two implementations against each other when there is
no single reference.

```mbti
pub struct RelationalOracle[Input, Output] {
  id : String
  validate_pair : (Input, Int, String, @model.ExecutionOutcome[Output], String, @model.ExecutionOutcome[Output]) -> @model.ValidationStatus
}
pub fn[Input, Output] RelationalOracle::new(String, (Input, Int, String, @model.ExecutionOutcome[Output], String, @model.ExecutionOutcome[Output]) -> @model.ValidationStatus) -> Self[Input, Output]
```

`validate_pair(input, step, left_id, left, right_id, right)` returns the
verdict for the pair; the runner attributes it to the right implementation.

```moonbit
test "a relational oracle" {
  let agree = @experiment.RelationalOracle::new("agree", (_ : Int, _, _, left : @model.ExecutionOutcome[Int], _, right) => {
    match (left, right) {
      (Value(a), Value(b)) if a == b => Valid
      (_, Unsupported(reason)) => Unsupported(reason)
      _ => Invalid("implementations disagree")
    }
  })
  inspect((agree.validate_pair)(1, 0, "a", Value(3), "b", Value(3)) is Valid, content="true")
  inspect((agree.validate_pair)(1, 0, "a", Value(3), "b", Value(4)) is Invalid(_), content="true")
}
```

### `OracleSpec`

`OracleSpec` selects the oracles of a case.

```mbti
pub(all) enum OracleSpec[Input, Expected, Output, Context] {
  Reference(ReferenceOracle[Input, Expected, Output, Context])
  Relational(RelationalOracle[Input, Output])
  ReferenceAndRelational(ReferenceOracle[Input, Expected, Output, Context], RelationalOracle[Input, Output])
}
```

With `ReferenceAndRelational` the runner runs both checks and reports each
separately.

## Shrinking

### `Shrinker`

`Shrinker` proposes smaller variants of a failing input.

```mbti
pub struct Shrinker[Input] {
  candidates : (Input) -> Array[Input]
  text : (Input) -> String
  max_steps : Int
}
pub fn[Input] Shrinker::new((Input) -> Array[Input], (Input) -> String, max_steps? : Int) -> Self[Input]
```

`candidates(x)` lists smaller inputs, most aggressive first. `text` renders an
accepted candidate for the shrink path. `max_steps` (default `128`) bounds the
number of candidates tried.

### `shrink`

`shrink` minimizes an input while a predicate keeps holding.

```mbti
pub fn[Input] shrink(Input, Shrinker[Input], (Input) -> Bool) -> (Input, Array[String])
```

Starting from the input, it repeatedly takes the first candidate for which the
predicate is true, until no candidate satisfies it or `max_steps` candidates
have been tried. It returns the last accepted input and the texts of the
accepted candidates in order. The initial input is not tested.

```moonbit
test "shrink a failing size" {
  let shrinker = @experiment.Shrinker::new(
    (n : Int) => if n <= 1 { [] } else { [n / 2, n - 1] },
    n => n.to_string(),
  )
  let (smallest, path) = @experiment.shrink(64, shrinker, n => n >= 5)
  inspect(smallest, content="5")
  debug_inspect(path, content="[\"32\", \"16\", \"8\", \"7\", \"6\", \"5\"]")
}
```

## Crossover analysis

### `ScaleDomain`

`ScaleDomain` lists the scales of an analysis with their order and text.

```mbti
pub struct ScaleDomain[Scale] {
  values : Array[Scale]
  compare : (Scale, Scale) -> Int
  text : (Scale) -> String
}
pub fn[Scale] ScaleDomain::new(Array[Scale], (Scale, Scale) -> Int, (Scale) -> String) -> Self[Scale]
```

`crossover_from_labels` reads `values` in the given order and does not sort
them; pass them sorted.

### `comparator_label`

`comparator_label` turns a relative delta into a label for crossover analysis.

```mbti
pub fn comparator_label(Double, Double) -> String
```

`comparator_label(r, t)` is `"A"` when $r \le -t$, else `"B"` when $r \ge t$,
else `"Unknown"`, the same ordered chain as the decision of
`@stats.compare_paired`. Pass the relative delta of A measured against B as the
baseline, so that `"A"` means A is faster.

> [!WARNING]
> The threshold is not validated
> ([issue #1](https://github.com/Luna-Flow/mare_mark/issues/1)). With $t = 0$
> an exact tie ($r = 0$) is `"A"`; with $t < 0$ small slowdowns of A are `"A"`
> too; with $t$ = `NaN` every delta is `"Unknown"`, so `crossover_from_labels`
> can only report `NoCrossover`. Pass a finite, positive threshold.

### `crossover_from_labels`

`crossover_from_labels` finds the scale at which the preferred implementation
changes.

```mbti
pub fn[Scale] crossover_from_labels(ScaleDomain[Scale], Array[String]) -> @model.CrossoverResult[Scale]
```

`labels[i]` is the verdict at `values[i]`. A transition is a pair of adjacent
labels that differ and are both not `"Unknown"`.

| Situation | Result |
| --- | --- |
| no labels, or a different number of labels and values | `Inconclusive("label/domain length mismatch", labels)` |
| no transition | `NoCrossover("no stable label transition", labels)` |
| exactly one transition, between $i-1$ and $i$ | `Found(ScaleBoundary(values[i-1], values[i]), "piecewise-confirmed", labels)` |
| more than one transition | `NonMonotonic(labels)` |

```moonbit
test "find a crossover" {
  let domain = @experiment.ScaleDomain::new([16, 64, 256, 1024], (a, b) => a.compare(b), n => n.to_string())
  let labels = [-12.0, -4.0, 6.0, 15.0].map(r => @experiment.comparator_label(r, 3.0))
  debug_inspect(labels, content="[\"A\", \"A\", \"B\", \"B\"]")
  guard @experiment.crossover_from_labels(domain, labels) is Found(boundary, _, _) else {
    fail("expected a crossover")
  }
  inspect(boundary.below, content="64")
  inspect(boundary.at_or_above, content="256")
}
```
