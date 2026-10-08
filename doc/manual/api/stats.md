# stats API

`Luna-Flow/mare_mark/stats` turns arrays of timings into descriptive summaries,
paired comparisons, seeded bootstrap intervals and outlier-filtered views. Every
function is pure: it reads its arguments, allocates its result and never touches
an event stream. The mathematics behind each estimator is derived in the
[stats design](../design/stats.md).

Source: [`src/stats/stats.mbt`](../../../src/stats/stats.mbt).

```text
import {
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/stats",
}
```

## Descriptive summaries

### `SummaryStats`

`SummaryStats` holds the descriptive statistics of one sample.

```mbti
pub struct SummaryStats {
  count : Int
  min : Double
  max : Double
  mean : Double
  median : Double
  mad : Double
  q1 : Double
  q3 : Double
  iqr : Double
  std_dev : Double
}
```

For a sample $x_1, \dots, x_n$ with order statistics
$x_{(1)} \le \dots \le x_{(n)}$ the fields are:

| Field | Definition |
| --- | --- |
| `count` | $n$ |
| `min`, `max` | $x_{(1)}$, $x_{(n)}$ |
| `mean` | $\bar x = \frac{1}{n}\sum_i x_i$ |
| `median` | $Q(0.5)$ |
| `q1`, `q3` | $Q(0.25)$, $Q(0.75)$ |
| `iqr` | $Q(0.75) - Q(0.25)$ |
| `mad` | median of $\lvert x_i - Q(0.5)\rvert$, without the normal-consistency factor $1.4826$ |
| `std_dev` | population standard deviation $\sqrt{\frac{1}{n}\sum_i (x_i - \bar x)^2}$ |

$Q(p)$ is the linearly interpolated sample quantile (Hyndman–Fan type 7):
with $h = (n-1)p$,

$$
Q(p) = x_{(\lfloor h \rfloor + 1)} + (h - \lfloor h \rfloor)\,\bigl(x_{(\lfloor h \rfloor + 2)} - x_{(\lfloor h \rfloor + 1)}\bigr).
$$

The fields are read-only outside the package; values are produced by
`summarize`.

### `summarize`

`summarize` computes a `SummaryStats` for an array of values.

```mbti
pub fn summarize(Array[Double]) -> SummaryStats
```

The input is copied before sorting, so the caller's array keeps its order. An
empty array gives `count == 0` and every other field `0.0`; test `count` before
reading the other fields. Non-finite values are not rejected: a `NaN` makes the
mean and standard deviation `NaN` and gives the sort an unspecified position
for it. Cost: $O(n \log n)$ time for the two sorts, $O(n)$ extra space.

```moonbit
test "summarize a sample" {
  let summary = @stats.summarize([4.0, 1.0, 3.0, 2.0, 100.0])
  inspect(summary.count, content="5")
  inspect(summary.median, content="3")
  inspect(summary.q1, content="2")
  inspect(summary.q3, content="4")
  inspect(summary.mad, content="1")
  inspect(summary.mean, content="22")
}
```

The mean is pulled to `22` by one slow value; the median, quartiles and MAD are
not. That is why the comparisons below are built on medians.

## Paired comparisons

### `Decision`

`Decision` is the verdict of a paired comparison.

```mbti
pub enum Decision {
  Faster
  Slower
  Equivalent
  Invalid
  Unknown
}
```

| Constructor | Meaning |
| --- | --- |
| `Faster` | the relative median delta is at or below $-t$ |
| `Slower` | the relative median delta is at or above $t$ |
| `Equivalent` | the relative median delta lies strictly between $-t$ and $t$ |
| `Invalid` | the two arrays have different lengths |
| `Unknown` | there are no pairs |

Here $t$ is the practical threshold passed as `practical_delta_pct`.
`Decision` is readonly outside the package: you match on it, you do not build
it.

### `Interval`

`Interval` is a pair of bounds labelled with the phase it belongs to.

```mbti
pub struct Interval {
  low : Double
  high : Double
  mode : @model.IntervalMode
}
```

`compare_paired` fills it with the interquartile range of the paired deltas;
`bootstrap_interval` and `compare_paired_with_bootstrap` fill it with a
percentile bootstrap interval. `mode` is a label copied from the caller; it
does not change the computation.

### `Comparison`

`Comparison` is the result of comparing a candidate against a baseline.

```mbti
pub struct Comparison {
  baseline_id : String
  candidate_id : String
  relative_delta_pct : Double
  speedup : Double
  interval : Interval
  decision : Decision
  valid_samples : Int
}
```

| Field | Meaning |
| --- | --- |
| `relative_delta_pct` | $r = 100 \cdot \operatorname{med}(d) / \operatorname{med}(b)$, or `0.0` when $\operatorname{med}(b) = 0$ |
| `speedup` | $\operatorname{med}(b) / (\operatorname{med}(b) + \operatorname{med}(d))$, or `1.0` when $\operatorname{med}(d) = 0$ |
| `interval` | bounds on the paired deltas, in the unit of the input (for example µs) |
| `decision` | the `Decision` described above |
| `valid_samples` | number of pairs, $\min(\lvert b\rvert, \lvert c\rvert)$ |

$b$ is the baseline array, $c$ the candidate array and $d_i = c_i - b_i$ the
paired deltas. A `speedup` above `1.0` means the candidate is faster.

### `paired_deltas`

`paired_deltas` subtracts each baseline value from the candidate value at the
same index.

```mbti
pub fn paired_deltas(Array[Double], Array[Double]) -> Array[Double]
```

The first argument is the baseline, the second the candidate. The result has
$\min(\lvert b\rvert, \lvert c\rvert)$ elements: surplus values of the longer
array are ignored, so check the lengths yourself when a mismatch is an error.

### `compare_paired`

`compare_paired` compares two aligned arrays of timings with a practical
threshold.

```mbti
pub fn compare_paired(String, String, Array[Double], Array[Double], Double, @model.IntervalMode) -> Comparison
```

Arguments: baseline id, candidate id, baseline values, candidate values, the
practical threshold $t$ in percent, and the interval label. Index $i$ of both
arrays must describe the same dataset, repetition and block. The decision uses
the point estimate $r$ only; the interval is the interquartile range
$[Q_d(0.25), Q_d(0.75)]$ of the deltas and is descriptive, not a confidence
interval.

> [!WARNING]
> With $t = 0$ an exact tie ($r = 0$) is classified as `Faster`, because the
> test is $r \le -t$. Use a positive threshold.

```moonbit
test "paired comparison" {
  let baseline = [100.0, 102.0, 98.0, 101.0, 99.0, 103.0, 97.0, 100.0]
  let candidate = [90.0, 93.0, 88.0, 92.0, 91.0, 94.0, 87.0, 90.0]
  let comparison = @stats.compare_paired(
    "baseline",
    "candidate",
    baseline,
    candidate,
    2.0,
    @model.confirmatory_interval(),
  )
  inspect(comparison.relative_delta_pct, content="-9.5")
  inspect(comparison.speedup, content="1.1049723756906078")
  inspect(comparison.interval.low, content="-10")
  inspect(comparison.interval.high, content="-9")
  inspect(@stats.is_faster(comparison), content="true")
}
```

### `is_faster`

`is_faster` reports whether a comparison's decision is `Faster`.

```mbti
pub fn is_faster(Comparison) -> Bool
```

It is a convenience for dashboards and gates. Record the whole `Comparison`
next to it: `false` covers `Slower`, `Equivalent`, `Invalid` and `Unknown`
alike.

## Bootstrap intervals

### `BootstrapError`

`BootstrapError` explains why a bootstrap interval could not be computed.

```mbti
pub(all) enum BootstrapError {
  EmptySamples
  MismatchedPairs(Int, Int)
  InvalidResamples(Int)
  InvalidConfidence(Double)
  NonFiniteSample(Int)
}
```

| Constructor | Raised when |
| --- | --- |
| `EmptySamples` | there is nothing to resample |
| `MismatchedPairs(baseline, candidate)` | the paired arrays have different lengths |
| `InvalidResamples(count)` | the resample count is not positive |
| `InvalidConfidence(pct)` | the confidence is not a finite number strictly between 0 and 100 |
| `NonFiniteSample(index)` | the value at `index` is `NaN` or infinite |

### `bootstrap_interval`

`bootstrap_interval` computes a seeded percentile bootstrap interval for the
median of a sample.

```mbti
pub fn bootstrap_interval(Array[Double], UInt64, Int, Double, @model.IntervalMode) -> Result[Interval, BootstrapError]
```

Arguments: the values, the seed, the number of resamples $B$, the confidence
level $\gamma$ in percent and the interval label. The function draws $B$
resamples of size $n$ with replacement, takes the median of each, and returns
the type-7 quantiles at $\alpha/2$ and $1-\alpha/2$ of those medians, where
$\alpha = 1 - \gamma/100$. The checks run in the order empty input, resample
count, confidence, finiteness, and the first failure is returned.

The result is a function of its arguments only: the same values, seed, $B$ and
$\gamma$ give the same bounds on every target. The bounds always satisfy
$\min_i x_i \le$ `low` $\le$ `high` $\le \max_i x_i$. Seed `0` is replaced by a
fixed non-zero constant. Cost: $O(B\, n \log n)$ time and $O(n + B)$ space.

```moonbit
test "bootstrap interval of a median" {
  let deltas = [-10.0, -9.0, -10.0, -9.0, -8.0, -9.0, -10.0, -10.0]
  let interval = @stats.bootstrap_interval(
    deltas,
    42UL,
    1000,
    95.0,
    @model.confirmatory_interval(),
  ).unwrap()
  inspect(interval.low, content="-10")
  inspect(interval.high, content="-9")
  let error = @stats.bootstrap_interval(
    deltas,
    42UL,
    1000,
    100.0,
    @model.confirmatory_interval(),
  )
  inspect(error is Err(@stats.BootstrapError::InvalidConfidence(_)), content="true")
}
```

### `compare_paired_with_bootstrap`

`compare_paired_with_bootstrap` is `compare_paired` with the interquartile
interval replaced by a bootstrap interval of the median paired delta.

```mbti
pub fn compare_paired_with_bootstrap(String, String, Array[Double], Array[Double], Double, @model.IntervalMode, UInt64, Int, Double) -> Result[Comparison, BootstrapError]
```

The first six arguments are those of `compare_paired`; the last three are the
seed, the resample count and the confidence in percent. Unlike
`compare_paired`, unequal lengths are an error (`MismatchedPairs`) and so are
empty arrays (`EmptySamples`). `relative_delta_pct`, `speedup`, `decision` and
`valid_samples` are the same as from `compare_paired`; only `interval` changes.
The interval is in the unit of the input, while the decision is in percent.

```moonbit
test "paired comparison with a bootstrap interval" {
  let baseline = [100.0, 102.0, 98.0, 101.0, 99.0, 103.0, 97.0, 100.0]
  let candidate = [90.0, 93.0, 88.0, 92.0, 91.0, 94.0, 87.0, 90.0]
  let comparison = @stats.compare_paired_with_bootstrap(
    "baseline",
    "candidate",
    baseline,
    candidate,
    2.0,
    @model.confirmatory_interval(),
    7UL,
    2000,
    95.0,
  ).unwrap()
  inspect(comparison.decision is Faster, content="true")
  inspect(comparison.interval.low, content="-10")
  inspect(comparison.interval.high, content="-9")
}
```

## Outlier views

### `filter_outliers`

`filter_outliers` returns the values that an outlier policy keeps, in their
original order.

```mbti
pub fn filter_outliers(Array[Double], @model.OutlierPolicy) -> Array[Double]
```

| Policy | Kept values |
| --- | --- |
| `ReportOnly` | all values (a copy) |
| `TukeyFence` | $Q(0.25) - 1.5\,\mathrm{IQR} \le x \le Q(0.75) + 1.5\,\mathrm{IQR}$ |
| `MADTrim` | $\lvert x - Q(0.5)\rvert \le 3\,\mathrm{MAD}$ |

The input array is never modified. When more than half of the values are equal,
the MAD is `0` and `MADTrim` keeps only the values equal to the median. Use the
result for a derived view; keep the raw observations.

```moonbit
test "outlier views" {
  let values = [10.0, 11.0, 10.0, 12.0, 11.0, 48.0]
  debug_inspect(
    @stats.filter_outliers(values, @model.OutlierPolicy::TukeyFence),
    content="[10, 11, 10, 12, 11]",
  )
  inspect(values.length(), content="6")
}
```