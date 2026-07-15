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
pub(all) enum BootstrapError {
  EmptySamples
  MismatchedPairs(Int, Int)
  InvalidResamples(Int)
  InvalidConfidence(Double)
  NonFiniteSample(Int)
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
fn bootstrap_next(state : UInt64) -> UInt64 {
  let mut value = if state == 0UL { 88172645463393265UL } else { state }
  value = value ^ (value >> 12)
  value = value ^ (value << 25)
  value = value ^ (value >> 27)
  value * 2685821657736338717UL
}

///|
pub fn bootstrap_interval(
  values : Array[Double],
  seed : UInt64,
  resamples : Int,
  confidence_pct : Double,
  mode : @model.IntervalMode,
) -> Result[Interval, BootstrapError] {
  if values.is_empty() {
    return Err(EmptySamples)
  }
  if resamples <= 0 {
    return Err(InvalidResamples(resamples))
  }
  if confidence_pct.is_nan() ||
    confidence_pct.is_inf() ||
    confidence_pct <= 0.0 ||
    confidence_pct >= 100.0 {
    return Err(InvalidConfidence(confidence_pct))
  }
  for index = 0; index < values.length(); index = index + 1 {
    if values[index].is_nan() || values[index].is_inf() {
      return Err(NonFiniteSample(index))
    }
  }
  let count = resamples.max(1)
  let mut state = if seed == 0UL { 88172645463393265UL } else { seed }
  let estimates : Array[Double] = []
  for resample = 0; resample < count; resample = resample + 1 {
    let sample = Array::makei(values.length(), _ => {
      state = bootstrap_next(state)
      values[(state % values.length().to_uint64()).to_int()]
    })
    sample.sort()
    estimates.push(quantile(sample, 0.5))
  }
  estimates.sort()
  let alpha = (100.0 - confidence_pct) / 100.0 / 2.0
  Ok({
    low: quantile(estimates, alpha),
    high: quantile(estimates, 1.0 - alpha),
    mode,
  })
}

///|
pub fn compare_paired_with_bootstrap(
  baseline_id : String,
  candidate_id : String,
  baseline : Array[Double],
  candidate : Array[Double],
  practical_delta_pct : Double,
  mode : @model.IntervalMode,
  seed : UInt64,
  resamples : Int,
  confidence_pct : Double,
) -> Result[Comparison, BootstrapError] {
  if baseline.length() != candidate.length() {
    return Err(MismatchedPairs(baseline.length(), candidate.length()))
  }
  if baseline.is_empty() {
    return Err(EmptySamples)
  }
  let comparison = compare_paired(
    baseline_id, candidate_id, baseline, candidate, practical_delta_pct, mode,
  )
  let interval = match
    bootstrap_interval(
      paired_deltas(baseline, candidate),
      seed,
      resamples,
      confidence_pct,
      mode,
    ) {
    Ok(interval) => interval
    Err(error) => return Err(error)
  }
  Ok({
    baseline_id: comparison.baseline_id,
    candidate_id: comparison.candidate_id,
    relative_delta_pct: comparison.relative_delta_pct,
    speedup: comparison.speedup,
    interval,
    decision: comparison.decision,
    valid_samples: comparison.valid_samples,
  })
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
