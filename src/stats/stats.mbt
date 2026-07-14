///|
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

///|
pub enum Decision {
  Faster
  Slower
  Equivalent
  Invalid
  Unknown
}

///|
pub struct Interval {
  low : Double
  high : Double
  mode : @model.IntervalMode
}

///|
pub struct Comparison {
  baseline_id : String
  candidate_id : String
  relative_delta_pct : Double
  speedup : Double
  interval : Interval
  decision : Decision
  valid_samples : Int
}

///|
pub fn is_faster(comparison : Comparison) -> Bool {
  match comparison.decision {
    Faster => true
    _ => false
  }
}

///|
fn quantile(sorted : Array[Double], fraction : Double) -> Double {
  if sorted.is_empty() {
    0.0
  } else {
    let position = fraction * (sorted.length() - 1).to_double()
    let lower = position.floor().to_int()
    let upper = position.ceil().to_int()
    if lower == upper {
      sorted[lower]
    } else {
      let weight = position - lower.to_double()
      sorted[lower] * (1.0 - weight) + sorted[upper] * weight
    }
  }
}

///|
pub fn summarize(values : Array[Double]) -> SummaryStats {
  if values.is_empty() {
    {
      count: 0,
      min: 0.0,
      max: 0.0,
      mean: 0.0,
      median: 0.0,
      mad: 0.0,
      q1: 0.0,
      q3: 0.0,
      iqr: 0.0,
      std_dev: 0.0,
    }
  } else {
    let sorted = values.copy()
    sorted.sort()
    let sum = for value in values; sum = 0.0 {
      continue sum + value
    } nobreak {
      sum
    }
    let mean = sum / values.length().to_double()
    let variance_sum = for value in values; total = 0.0 {
      let difference = value - mean
      continue total + difference * difference
    } nobreak {
      total
    }
    let median = quantile(sorted, 0.5)
    let deviations = values.map(value => (value - median).abs())
    deviations.sort()
    let q1 = quantile(sorted, 0.25)
    let q3 = quantile(sorted, 0.75)
    {
      count: values.length(),
      min: sorted[0],
      max: sorted[sorted.length() - 1],
      mean,
      median,
      mad: quantile(deviations, 0.5),
      q1,
      q3,
      iqr: q3 - q1,
      std_dev: (variance_sum / values.length().to_double()).sqrt(),
    }
  }
}

///|
pub fn paired_deltas(
  baseline : Array[Double],
  candidate : Array[Double],
) -> Array[Double] {
  let count = baseline.length().min(candidate.length())
  Array::makei(count, index => candidate[index] - baseline[index])
}

///|
pub fn compare_paired(
  baseline_id : String,
  candidate_id : String,
  baseline : Array[Double],
  candidate : Array[Double],
  practical_delta_pct : Double,
  mode : @model.IntervalMode,
) -> Comparison {
  let deltas = paired_deltas(baseline, candidate)
  let baseline_stats = summarize(baseline)
  let delta_stats = summarize(deltas)
  let relative_delta_pct = if baseline_stats.median == 0.0 {
    0.0
  } else {
    delta_stats.median / baseline_stats.median * 100.0
  }
  let speedup = if delta_stats.median == 0.0 {
    1.0
  } else {
    baseline_stats.median / (baseline_stats.median + delta_stats.median)
  }
  let decision = if baseline.length() != candidate.length() {
    Invalid
  } else if deltas.is_empty() {
    Unknown
  } else if relative_delta_pct <= -practical_delta_pct {
    Faster
  } else if relative_delta_pct >= practical_delta_pct {
    Slower
  } else {
    Equivalent
  }
  {
    baseline_id,
    candidate_id,
    relative_delta_pct,
    speedup,
    interval: { low: delta_stats.q1, high: delta_stats.q3, mode },
    decision,
    valid_samples: deltas.length(),
  }
}

///|
pub fn filter_outliers(
  values : Array[Double],
  policy : @model.OutlierPolicy,
) -> Array[Double] {
  match policy {
    @model.OutlierPolicy::ReportOnly => values.copy()
    @model.OutlierPolicy::TukeyFence => {
      let stats = summarize(values)
      let lower = stats.q1 - 1.5 * stats.iqr
      let upper = stats.q3 + 1.5 * stats.iqr
      values.filter(value => value >= lower && value <= upper)
    }
    @model.OutlierPolicy::MADTrim => {
      let stats = summarize(values)
      let threshold = 3.0 * stats.mad
      values.filter(value => (value - stats.median).abs() <= threshold)
    }
  }
}
