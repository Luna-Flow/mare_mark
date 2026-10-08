# tune tutorial

This tutorial runs a small tuning loop: define a candidate space, score
candidates from timing samples, choose a winner with a practical threshold, look
at the trade-offs on a Pareto front, and restrict a large space to a
reproducible random subset. Timings are given as numbers so the examples are
deterministic; in practice they come from `runner` observations.

| I want to | Use |
| --- | --- |
| describe the candidates | `@tune.CandidateSpace::new` |
| score a candidate from timings | `@tune.score_samples` |
| pick a winner with practical ties | `@tune.select_best` |
| see the speed and size trade-offs | `@tune.pareto_frontier` |
| score every candidate that meets the constraints | `@tune.exhaustive_scores` |
| measure a reproducible subset | `@tune.seeded_order`, then a prefix |

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/tune",
}
```

```moonbit
test "pick a block size" {
  let samples = [
    ("block-16", [5.1, 5.0, 5.3]),
    ("block-32", [4.2, 4.4, 4.1]),
    ("block-64", [4.3, 4.2, 4.3]),
  ]
  let scores = samples.map(entry => @tune.score_samples(entry.0, entry.1, 0.0))
  inspect(@tune.select_best(scores, 0.0, true).unwrap().candidate_id, content="block-32")
}
```

## Everyday tasks

### Prefer the cheaper of two tied candidates

`block-64` is within 3 % of `block-32` but needs a quarter of the workspace.
With a 5 % threshold and workspace as secondary metric, it wins:

```moonbit
test "ties go to the smaller workspace" {
  let scores = [
    @tune.score_samples("block-32", [4.2, 4.4, 4.1], 65536.0),
    @tune.score_samples("block-64", [4.3, 4.2, 4.3], 16384.0),
  ]
  inspect(@tune.select_best(scores, 5.0, true).unwrap().candidate_id, content="block-64")
}
```

### Show the trade-offs

```moonbit
test "time versus memory" {
  let front = @tune.pareto_frontier([
    @tune.score_samples("tiny", [9.0], 1024.0),
    @tune.score_samples("small", [5.0], 4096.0),
    @tune.score_samples("medium", [5.5], 8192.0),
    @tune.score_samples("large", [4.0], 65536.0),
  ])
  debug_inspect(front.map(s => s.candidate_id), content="[\"large\", \"small\", \"tiny\"]")
}
```

`medium` is slower and larger than `small`, so it is not on the front.

### Search a space with constraints

```moonbit
test "exhaustive search with constraints" {
  let space = @tune.CandidateSpace::new(
    () => [(16, 16), (32, 32), (64, 64), (128, 128)],
    tile => tile.0.to_string() + "x" + tile.1.to_string(),
    tile => tile.0 * tile.1 * 8 <= 65536,
    _ => [],
  )
  let measured : Map[String, Array[Double]] = Map([
    ("16x16", [6.0, 6.1]), ("32x32", [4.1, 4.0]), ("64x64", [3.9, 4.0]),
  ])
  let result = @tune.exhaustive_scores(space, 4, tile => {
    let id = tile.0.to_string() + "x" + tile.1.to_string()
    @tune.score_samples(id, measured.get(id).unwrap_or([]), 0.0)
  })
  inspect(result.policy, content="global:64x64")
  inspect(result.build_events[3].reason, content="constraint")
}
```

The 128×128 tile needs 128 KiB and is rejected before it is measured.

### Sample a large space reproducibly

```moonbit
test "a seeded subset" {
  let all = Array::makei(100, i => "candidate-" + i.to_string())
  let first_five = @tune.seeded_order(all, 2026UL, id => id)[:5].to_owned()
  let again = @tune.seeded_order(all.rev(), 2026UL, id => id)[:5].to_owned()
  inspect(first_five == again, content="true")
  inspect(
    first_five.join(" "),
    content="candidate-7 candidate-66 candidate-10 candidate-14 candidate-47",
  )
}
```

The same seed gives the same candidates whatever order the space is listed
in, and the candidates are spread over the whole space even though the ids
differ only in their last characters. Record the seed with the result.

## Going further

- **Confirm finalists.** Re-measure the best few with
  `@tune.confirmation_count(base, relative_iqr, budget)` fresh samples and
  select again on those; the [tune design](../design/tune.md) explains why the
  first selection is optimistic.
- **Hold out shapes.** Choose with some shapes, then check the winner on a
  `ShapeHoldout`.
- **Measure with the runner.** Wrap each candidate in a
  `@runner.Implementation`, run them in one case so they share blocks, and
  feed per-candidate confirmatory medians to `score_samples`.
- **A worked example.** [`tune_gemm`](tune_gemm.md) applies all of this to
  blocked matrix multiplication.

## Common pitfalls

- **Selecting on exploration data only.** The winner's curse makes it look
  better than it is.
- **A threshold of zero with noisy data.** Ties are then decided by noise.
- **Ids that are not unique.** Selection and ordering assume unique ids.
- **Comparing subsets across versions.** The order for a seed changed when
  `seeded_order` gained its finalizer; regenerate recorded subsets.
- **Trusting the `exhaustive_scores` policy string.** `global:<id>` is the raw
  minimum, without practical ties or confirmation; decide with `select_best`.

## Next steps

- [tune API](../api/tune.md), [tune design](../design/tune.md).
- [tune_gemm tutorial](tune_gemm.md).
