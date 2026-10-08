# experiment tutorial

This tutorial covers the correctness tools of a benchmark: an oracle with a
tolerance, a relational check between implementations, a shrinker that makes
failures small, and a crossover analysis that tells you at which size to
switch implementations. Every example is a complete test.

| I want to | Use |
| --- | --- |
| check results against a reference | `@experiment.ReferenceOracle::equal` or `ReferenceOracle::new` |
| compare floating-point results with a tolerance | a comparator in `ReferenceOracle::equal` |
| check implementations against each other | `@experiment.RelationalOracle::new` |
| make a failing input small | `@experiment.Shrinker::new` and `@experiment.shrink` |
| find the scale where the winner changes | `@experiment.comparator_label` and `@experiment.crossover_from_labels` |

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/experiment",
}
```

```moonbit
test "is the fast sum right?" {
  let oracle = @experiment.ReferenceOracle::equal(
    "exact-sum",
    (xs : Array[Int]) => xs.fold(init=0, (a, b) => a + b),
    (expected : Int, actual : Int) => expected == actual,
  )
  let input = [1, 2, 3, 4]
  let verdict = @experiment.validate_reference(oracle, input, 0, Value(10), Value(10), "fast-sum", "4")
  inspect(verdict.status is Valid, content="true")
}
```

## Everyday tasks

### Compare floating-point results with a tolerance

A reassociated sum differs from the left-to-right sum in the last bits. Accept
a relative error instead of demanding equality:

```moonbit
test "relative tolerance" {
  let close = (expected : Double, actual : Double) => {
    (expected - actual).abs() <= 1.0e-12 * expected.abs().max(1.0)
  }
  let oracle = @experiment.ReferenceOracle::equal("sum", (xs : Array[Double]) => xs.fold(init=0.0, (a, b) => a + b), close)
  let xs = [0.1, 0.2, 0.3]
  let pairwise = xs[0] + (xs[1] + xs[2])
  let verdict = @experiment.validate_reference(oracle, xs, 0, Value(0.1 + 0.2 + 0.3), Value(pairwise), "pairwise", "3")
  inspect(verdict.status is Valid, content="true")
}
```

### Check implementations against each other

Without a trusted reference, check that implementations agree:

```moonbit
test "implementations must agree" {
  let agree : @experiment.RelationalOracle[Int, Int] = @experiment.RelationalOracle::new("agree", (_, _, _, left, _, right) => {
    match (left, right) {
      (Value(a), Value(b)) => if a == b { Valid } else { Invalid("results differ") }
      _ => Invalid("missing result")
    }
  })
  let spec : @experiment.OracleSpec[Int, Int, Int, Unit] = Relational(agree)
  guard spec is Relational(oracle) else { fail("unexpected spec") }
  inspect((oracle.validate_pair)(5, 0, "loop", Value(10), "formula", Value(10)) is Valid, content="true")
}
```

Pass the `OracleSpec` to `@runner.BenchSpec::advanced`; the runner checks
every pair of implementations.

### Make a failure small

A list function fails for every list containing a negative number. Shrink the
failing input by dropping elements:

```moonbit
test "shrink a list" {
  let shrinker = @experiment.Shrinker::new(
    (xs : Array[Int]) => Array::makei(xs.length(), i => {
      let smaller = xs.copy()
      smaller.remove(i) |> ignore
      smaller
    }),
    xs => xs.length().to_string(),
  )
  let failing = [3, 8, -2, 7, 1]
  let (minimal, _) = @experiment.shrink(failing, shrinker, xs => xs.any(x => x < 0))
  debug_inspect(minimal, content="[-2]")
}
```

The runner calls the same algorithm when a `BenchSpec` has a `shrinker`, and
writes the minimal input into the failure event.

### Find where to switch implementations

Compare two implementations at several sizes, label each size, and look for
one clean transition:

```moonbit
test "crossover between two algorithms" {
  let sizes = [8, 32, 128, 512, 2048]
  let relative_delta_of_insertion_vs_merge = [-35.0, -12.0, 1.0, 18.0, 60.0]
  let labels = relative_delta_of_insertion_vs_merge.map(r => @experiment.comparator_label(r, 5.0))
  debug_inspect(labels, content="[\"A\", \"A\", \"Unknown\", \"B\", \"B\"]")
  let domain = @experiment.ScaleDomain::new(sizes, (a, b) => a.compare(b), n => n.to_string())
  let result = @experiment.crossover_from_labels(domain, labels)
  inspect(result is NoCrossover(_, _), content="true")
  let sharper = [-35.0, -12.0, -6.0, 18.0, 60.0].map(r => @experiment.comparator_label(r, 5.0))
  guard @experiment.crossover_from_labels(domain, sharper) is Found(boundary, _, _) else { fail("none") }
  inspect(boundary.at_or_above, content="512")
}
```

The first sequence has an `Unknown` between the `A` and `B` regions; the
analysis does not guess where in that gap the boundary lies and reports no
crossover. Measure the gap more finely, or decide the policy yourself.

## Going further

- Turn a `Found` boundary into a `@model.DeploymentPolicy::Piecewise`; see the
  [model tutorial](model.md).
- Combine a reference and a relational oracle with `ReferenceAndRelational`.
- The [experiment design](../design/experiment.md) proves that shrinking
  terminates and keeps the failure.

## Common pitfalls

- **Unsorted scales.** `crossover_from_labels` uses the order you give.
- **Equality for floating-point results.** Use a tolerance that matches the
  algorithm's error bound.
- **Shrinkers that grow the input.** Candidates should be smaller, or the
  budget is spent without progress.
- **Reading `NonMonotonic` as a crossover.** It is not; the preference flips.
- **A zero or `NaN` threshold in `comparator_label`.** With `0.0` a tie is
  labelled `"A"`; with `NaN` every label is `"Unknown"` and no crossover can
  be found. Use a finite, positive threshold.

## Next steps

- [experiment API](../api/experiment.md), [experiment design](../design/experiment.md).
- [runner tutorial](runner.md) for oracles inside a run.
