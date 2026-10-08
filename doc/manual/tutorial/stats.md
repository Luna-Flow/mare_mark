# stats tutorial

This tutorial turns timings into a decision you can defend: a robust summary, a
paired comparison against a practical threshold, a reproducible bootstrap
interval, and a cleaned view for plots that leaves the raw data alone. The
examples are complete tests; paste one into a package that imports the modules
shown below and run `moon test`.

| I want to | Use |
| --- | --- |
| describe one sample robustly | `@stats.summarize` |
| decide whether a candidate is faster | `@stats.compare_paired` with a positive threshold |
| add a reproducible interval | `@stats.compare_paired_with_bootstrap` or `@stats.bootstrap_interval` |
| pair observations from a run | filter by phase and implementation, sort by block |
| clean a plot without touching the data | `@stats.filter_outliers` |

## Quick start

Add the module and import the two packages:

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/stats",
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/runner",
  "moonbitlang/async",
}
```

Compare a candidate with a baseline measured in the same eight blocks:

```moonbit
test "is the candidate at least 2 % faster?" {
  let baseline = [100.0, 102.0, 98.0, 101.0, 99.0, 103.0, 97.0, 100.0]
  let candidate = [90.0, 93.0, 88.0, 92.0, 91.0, 94.0, 87.0, 90.0]
  let result = @stats.compare_paired(
    "baseline", "candidate", baseline, candidate, 2.0, @model.confirmatory_interval(),
  )
  inspect(result.relative_delta_pct, content="-9.5")
  inspect(@stats.is_faster(result), content="true")
}
```

The median paired delta is 9.5 % of the baseline median, well past the 2 %
threshold, so the decision is `Faster`.

## Everyday tasks

### Summarize one implementation

`summarize` gives classical and robust statistics side by side. When the mean
and the median disagree, the sample has a tail worth looking at.

```moonbit
test "summarize timings" {
  let timings = [12.0, 12.5, 11.75, 12.0, 12.25, 31.5, 12.25, 12.0]
  let summary = @stats.summarize(timings)
  inspect(summary.median, content="12.125")
  inspect(summary.mean, content="14.53125")
  inspect(summary.iqr, content="0.3125")
  inspect(summary.max, content="31.5")
}
```

One run of 31.5 µs drags the mean to 14.5 µs; the median stays at 12.1 µs.
Report the median and the IQR, and keep the maximum as a diagnostic.

### Decide with a practical threshold

The threshold states the smallest change you care about. A 1 % improvement is
`Faster` with a 0.5 % threshold and `Equivalent` with a 2 % threshold:

```moonbit
test "the threshold decides what counts" {
  let baseline = [100.0, 100.0, 100.0, 100.0]
  let candidate = [99.0, 99.0, 99.0, 99.0]
  let strict = @stats.compare_paired(
    "a", "b", baseline, candidate, 0.5, @model.confirmatory_interval(),
  )
  let lenient = @stats.compare_paired(
    "a", "b", baseline, candidate, 2.0, @model.confirmatory_interval(),
  )
  inspect(strict.decision is Faster, content="true")
  inspect(lenient.decision is Equivalent, content="true")
}
```

Choose the threshold before looking at the data, and record it with the result.

### Add a reproducible interval

`compare_paired_with_bootstrap` keeps the decision and replaces the
interquartile interval with a percentile bootstrap interval of the median
delta. Fix the seed and the number of resamples so that regenerating the report
gives the same numbers:

```moonbit
test "bootstrap interval of the median delta" {
  let baseline = [100.0, 102.0, 98.0, 101.0, 99.0, 103.0, 97.0, 100.0]
  let candidate = [90.0, 93.0, 88.0, 92.0, 91.0, 94.0, 87.0, 90.0]
  let first = @stats.compare_paired_with_bootstrap(
    "baseline", "candidate", baseline, candidate, 2.0,
    @model.confirmatory_interval(), 2026UL, 2000, 95.0,
  ).unwrap()
  let again = @stats.compare_paired_with_bootstrap(
    "baseline", "candidate", baseline, candidate, 2.0,
    @model.confirmatory_interval(), 2026UL, 2000, 95.0,
  ).unwrap()
  inspect(first.interval.low, content="-10")
  inspect(first.interval.high, content="-9")
  inspect(first.interval.low == again.interval.low, content="true")
}
```

The interval is in µs, the unit of the input: the median delta lies between
−10 µs and −9 µs at 95 % bootstrap confidence.

### Pair observations from a run

The runner emits one `Observation` per implementation and block. Pair them by
`block_id`, keep only valid confirmatory observations, and compare. This
example runs a real benchmark, so it shows only the numbers that do not depend
on the machine:

```moonbit
fn paired_confirmatory(
  observations : Array[@model.Observation],
  baseline_id : String,
  candidate_id : String,
  dataset_id : Int,
) -> (Array[Double], Array[Double]) {
  let baseline : Map[Int, Double] = Map([])
  let candidate : Map[Int, Double] = Map([])
  for observation in observations {
    if observation.valid &&
      observation.dataset_id == dataset_id &&
      observation.phase is Confirmatory {
      if observation.implementation_id == baseline_id {
        baseline[observation.block_id] = observation.raw_elapsed_us
      } else if observation.implementation_id == candidate_id {
        candidate[observation.block_id] = observation.raw_elapsed_us
      }
    }
  }
  let left = []
  let right = []
  for block_id, value in baseline {
    if candidate.get(block_id) is Some(other) {
      left.push(value)
      right.push(other)
    }
  }
  (left, right)
}

fn sum_to(n : Int) -> Int {
  let mut total = 0
  for i in 0..<n {
    total += i
  }
  total
}

async test "compare two implementations measured by the runner" {
  let loop_sum = @runner.Implementation::stateless("loop", "1", (n : Int) => {
    @model.OperationResult::completed(sum_to(n), ())
  })
  let formula = @runner.Implementation::stateless("formula", "1", (n : Int) => {
    @model.OperationResult::completed(n * (n - 1) / 2, ())
  })
  let plan = @runner.single_step("triangle", [1000])
    .with_immutable_input(context => context.dataset_key.scale, n => n.to_string())
    .compare([loop_sum, formula])
    .against_equal(n => n * (n - 1) / 2, (expected, actual) => expected == actual)
    .compile()
    .unwrap()
  let memory = @event.InMemorySink::new()
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(@model.ExecutionTarget::Native, "moonc", "", "i32"),
    @model.PerformanceEnvironment::new("native", "laptop", "default", 1, "monotonic"),
    @model.ProvenanceEnvironment::new("macos", "host", "now", "HEAD", "tutorial"),
  )
  let context = @runner.RunContext::new(
    environment,
    memory.as_sink(),
    42UL,
    @runner.ProtocolPreset::QuickCheck.validated(),
  )
  let summary = @runner.run(plan, context)
  inspect(summary.passed_count, content="2")
  let (baseline, candidate) = paired_confirmatory(
    memory.observations, "loop", "formula", 0,
  )
  let result = @stats.compare_paired(
    "loop", "formula", baseline, candidate, 5.0, @model.confirmatory_interval(),
  )
  inspect(result.valid_samples, content="3")
}
```

`QuickCheck` runs three confirmatory blocks, so there are three pairs. The
decision itself depends on your machine.

### Clean a plot without touching the data

Apply an outlier policy to a copy that feeds a plot, and keep the original for
the decision and the event stream:

```moonbit
test "derived outlier views" {
  let raw = [12.0, 12.5, 11.75, 12.0, 12.25, 31.5, 12.25, 12.0]
  let view = @stats.filter_outliers(raw, @model.OutlierPolicy::TukeyFence)
  inspect(view.length(), content="7")
  inspect(raw.length(), content="8")
  let everything = @stats.filter_outliers(raw, @model.OutlierPolicy::ReportOnly)
  inspect(everything == raw, content="true")
}
```

## Going further

**Check the interval against the threshold yourself.** The decision uses only
the point estimate. To require that the whole interval clears the threshold,
convert the bounds to percent of the baseline median:

```moonbit
test "interval in percent" {
  let baseline = [100.0, 102.0, 98.0, 101.0, 99.0, 103.0, 97.0, 100.0]
  let candidate = [90.0, 93.0, 88.0, 92.0, 91.0, 94.0, 87.0, 90.0]
  let result = @stats.compare_paired_with_bootstrap(
    "baseline", "candidate", baseline, candidate, 2.0,
    @model.confirmatory_interval(), 7UL, 2000, 95.0,
  ).unwrap()
  let reference = @stats.summarize(baseline).median
  let high_pct = result.interval.high / reference * 100.0
  inspect(high_pct, content="-9")
  inspect(high_pct <= -2.0, content="true")
}
```

Even the least favourable end of the interval is a 9 % improvement, so the
conclusion does not hinge on the point estimate.

**One decision per dataset.** Compare each dataset (scale) separately and feed
the per-scale labels to `@experiment.crossover_from_labels` to find the scale
where the winner changes; see the [experiment tutorial](experiment.md).

**Speedup from the relative delta.** `speedup` and `relative_delta_pct` are
tied by $s = 1/(1 + r/100)$ whenever the baseline median is not zero; the
[design page](../design/stats.md) derives it.

## Common pitfalls

- **Sorting arrays independently.** Pairing is positional. Sorting baseline
  and candidate separately destroys the pairing; sort pairs, not arrays.
- **Mixing phases or targets.** Exploratory and confirmatory observations,
  native and JS timings are different populations. Filter before pairing.
- **A zero, negative or `NaN` threshold.** The threshold is not validated. With
  `practical_delta_pct = 0.0` an exact tie is reported as `Faster`; a negative
  threshold reports small slowdowns as `Faster`; `NaN` reports everything,
  even a twofold slowdown, as `Equivalent`
  ([issue #1](https://github.com/Luna-Flow/mare_mark/issues/1)). Use a finite,
  positive threshold such as `2.0`.
- **Trusting the interval of a short run.** With a handful of blocks the
  bootstrap interval of the median covers the true median less often than its
  nominal level (87.5 % instead of 95 % for seven pairs); the
  [stats design](../design/stats.md) has the table.
- **`NaN` timings.** `compare_paired` does not reject them and can return any
  decision; the bootstrap functions return `NonFiniteSample`.
- **Reading `summarize([])`.** An empty sample returns zeros; check `count`.
- **Comparing interval and threshold directly.** The interval is in the input
  unit, the threshold in percent.
- **Deleting outliers from the source.** Filter a copy; the JSONL stream is the
  audit record.

## Next steps

- [stats API](../api/stats.md) for every function and error.
- [stats design](../design/stats.md) for the estimators, the bootstrap and the
  threshold rule.
- [runner tutorial](runner.md) to produce the observations compared here.
- [report tutorial](report.md) to publish the result.
