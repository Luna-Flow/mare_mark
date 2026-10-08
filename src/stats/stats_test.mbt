///|
test "summary reports robust statistics" {
  let summary = @stats.summarize([1.0, 2.0, 3.0, 4.0, 5.0])
  @test.assert_eq(summary.count, 5)
  @test.assert_eq(summary.median, 3.0)
  @test.assert_eq(summary.q1, 2.0)
  @test.assert_eq(summary.q3, 4.0)
}

///|
test "paired comparison uses practical threshold" {
  let comparison = @stats.compare_paired(
    "baseline",
    "candidate",
    [100.0, 100.0, 100.0],
    [90.0, 90.0, 90.0],
    5.0,
    @model.confirmatory_interval(),
  )
  @test.assert_eq(@stats.is_faster(comparison), true)
}

///|
test "incomplete paired blocks are invalid" {
  let comparison = @stats.compare_paired(
    "baseline",
    "candidate",
    [100.0, 101.0],
    [90.0],
    5.0,
    @model.confirmatory_interval(),
  )
  assert_true(comparison.decision is Invalid)
}

///|
test "bootstrap interval is deterministic and bounded by observed deltas" {
  let values = [-10.0, -9.0, -8.0, -7.0, -6.0]
  let first = @stats.bootstrap_interval(
    values,
    42UL,
    200,
    95.0,
    @model.confirmatory_interval(),
  ).unwrap()
  let second = @stats.bootstrap_interval(
    values,
    42UL,
    200,
    95.0,
    @model.confirmatory_interval(),
  ).unwrap()
  @test.assert_eq(first.low, second.low)
  @test.assert_eq(first.high, second.high)
  assert_true(first.low <= first.high)
  assert_true(first.low >= -10.0)
  assert_true(first.high <= -6.0)
}

///|
test "bootstrap comparison preserves decision and rejects invalid input" {
  let comparison = @stats.compare_paired_with_bootstrap(
    "baseline",
    "candidate",
    [100.0, 100.0, 100.0, 100.0],
    [90.0, 91.0, 89.0, 90.0],
    5.0,
    @model.confirmatory_interval(),
    7UL,
    100,
    95.0,
  ).unwrap()
  assert_true(comparison.decision is Faster)
  assert_true(comparison.interval.low <= comparison.interval.high)
  let invalid = @stats.bootstrap_interval(
    [],
    1UL,
    10,
    95.0,
    @model.exploratory_interval(),
  )
  assert_true(invalid is Err(@stats.BootstrapError::EmptySamples))
  assert_true(
    @stats.bootstrap_interval(
      [1.0],
      1UL,
      0,
      95.0,
      @model.exploratory_interval(),
    )
    is Err(@stats.BootstrapError::InvalidResamples(0)),
  )
  assert_true(
    @stats.bootstrap_interval(
      [1.0],
      1UL,
      10,
      100.0,
      @model.exploratory_interval(),
    )
    is Err(@stats.BootstrapError::InvalidConfidence(100.0)),
  )
  assert_true(
    @stats.bootstrap_interval(
      [1.0 / 0.0],
      1UL,
      10,
      95.0,
      @model.exploratory_interval(),
    )
    is Err(@stats.BootstrapError::NonFiniteSample(0)),
  )
  assert_true(
    @stats.compare_paired_with_bootstrap(
      "baseline",
      "candidate",
      [1.0, 2.0],
      [1.0],
      1.0,
      @model.confirmatory_interval(),
      1UL,
      10,
      95.0,
    )
    is Err(@stats.BootstrapError::MismatchedPairs(2, 1)),
  )
}

///|
test "summaries and paired decisions cover neutral and directional cases" {
  let empty = @stats.summarize([])
  @test.assert_eq(empty.count, 0)
  @test.assert_eq(empty.median, 0.0)
  let slower = @stats.compare_paired(
    "baseline",
    "candidate",
    [100.0, 100.0],
    [110.0, 111.0],
    5.0,
    @model.confirmatory_interval(),
  )
  let equivalent = @stats.compare_paired(
    "baseline",
    "candidate",
    [100.0, 100.0],
    [101.0, 99.0],
    5.0,
    @model.confirmatory_interval(),
  )
  let unknown = @stats.compare_paired(
    "baseline",
    "candidate",
    [],
    [],
    5.0,
    @model.exploratory_interval(),
  )
  assert_true(slower.decision is Slower)
  assert_true(equivalent.decision is Equivalent)
  assert_true(unknown.decision is Unknown)
  assert_true(!@stats.is_faster(slower))
}

///|
test "outlier policies keep raw values isolated" {
  let values = [1.0, 1.0, 1.0, 100.0]
  assert_true(
    @stats.filter_outliers(values, @model.OutlierPolicy::ReportOnly) == values,
  )
  assert_true(
    @stats.filter_outliers(values, @model.OutlierPolicy::TukeyFence).length() <
    values.length(),
  )
  assert_true(
    @stats.filter_outliers(values, @model.OutlierPolicy::MADTrim).length() <
    values.length(),
  )
  assert_true(values == [1.0, 1.0, 1.0, 100.0])
}

///|
fn compare_constant(
  baseline : Double,
  candidate : Double,
  practical_delta_pct : Double,
) -> @stats.Comparison {
  @stats.compare_paired(
    "baseline",
    "candidate",
    [baseline, baseline, baseline],
    [candidate, candidate, candidate],
    practical_delta_pct,
    @model.confirmatory_interval(),
  )
}

///|
test "an exact tie is equivalent for every valid threshold" {
  assert_true(compare_constant(10.0, 10.0, 0.0).decision is Equivalent)
  assert_true(compare_constant(10.0, 10.0, 2.0).decision is Equivalent)
  assert_true(compare_constant(10.0, 9.0, 0.0).decision is Faster)
  assert_true(compare_constant(10.0, 11.0, 0.0).decision is Slower)
}

///|
test "thresholds that are not finite and non-negative are invalid" {
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  assert_true(compare_constant(10.0, 20.0, nan).decision is Invalid)
  assert_true(compare_constant(10.0, 20.0, inf).decision is Invalid)
  assert_true(compare_constant(100.0, 103.0, -5.0).decision is Invalid)
  let boot = @stats.compare_paired_with_bootstrap(
    "baseline",
    "candidate",
    [10.0, 10.0, 10.0],
    [20.0, 20.0, 20.0],
    nan,
    @model.confirmatory_interval(),
    1UL,
    100,
    95.0,
  )
  assert_true(boot is Ok({ decision: Invalid, .. }))
}

///|
test "NaN propagates through summarize independent of its position" {
  let nan = 0.0 / 0.0
  for values in [[3.0, nan, 1.0, 2.0], [nan, 3.0, 1.0, 2.0], [1.0, 2.0, nan]] {
    let summary = @stats.summarize(values)
    @test.assert_eq(summary.count, values.length())
    assert_true(summary.min.is_nan())
    assert_true(summary.max.is_nan())
    assert_true(summary.median.is_nan())
    assert_true(summary.q1.is_nan())
    assert_true(summary.q3.is_nan())
    assert_true(summary.mad.is_nan())
    assert_true(summary.mean.is_nan())
  }
}

///|
test "NaN timings make a paired comparison invalid" {
  let nan = 0.0 / 0.0
  let comparison = @stats.compare_paired(
    "baseline",
    "candidate",
    [1.0, 2.0, 3.0],
    [nan, 2.0, 1.0],
    2.0,
    @model.confirmatory_interval(),
  )
  assert_true(comparison.relative_delta_pct.is_nan())
  assert_true(comparison.decision is Invalid)
}

///|
test "outlier filters drop NaN and fence the remaining values" {
  let nan = 0.0 / 0.0
  let values = [10.0, nan, 11.0, 10.0, 12.0, 11.0, 48.0]
  @test.assert_eq(
    @stats.filter_outliers(values, @model.OutlierPolicy::TukeyFence),
    [10.0, 11.0, 10.0, 12.0, 11.0],
  )
  @test.assert_eq(
    @stats.filter_outliers(values, @model.OutlierPolicy::MADTrim),
    [10.0, 11.0, 10.0, 12.0, 11.0],
  )
}
