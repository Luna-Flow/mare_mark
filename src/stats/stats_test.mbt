///|
test "summary reports robust statistics" {
  let summary = summarize([1.0, 2.0, 3.0, 4.0, 5.0])
  @test.assert_eq(summary.count, 5)
  @test.assert_eq(summary.median, 3.0)
  @test.assert_eq(summary.q1, 2.0)
  @test.assert_eq(summary.q3, 4.0)
}

///|
test "paired comparison uses practical threshold" {
  let comparison = compare_paired(
    "baseline",
    "candidate",
    [100.0, 100.0, 100.0],
    [90.0, 90.0, 90.0],
    5.0,
    @model.confirmatory_interval(),
  )
  @test.assert_eq(is_faster(comparison), true)
}

///|
test "incomplete paired blocks are invalid" {
  let comparison = compare_paired(
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
  let first = bootstrap_interval(
    values,
    42UL,
    200,
    95.0,
    @model.confirmatory_interval(),
  ).unwrap()
  let second = bootstrap_interval(
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
  let comparison = compare_paired_with_bootstrap(
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
  let invalid = bootstrap_interval(
    [],
    1UL,
    10,
    95.0,
    @model.exploratory_interval(),
  )
  assert_true(invalid is Err(BootstrapError::EmptySamples))
  assert_true(
    bootstrap_interval([1.0], 1UL, 0, 95.0, @model.exploratory_interval())
    is Err(BootstrapError::InvalidResamples(0)),
  )
  assert_true(
    bootstrap_interval([1.0], 1UL, 10, 100.0, @model.exploratory_interval())
    is Err(BootstrapError::InvalidConfidence(100.0)),
  )
  assert_true(
    bootstrap_interval(
      [1.0 / 0.0],
      1UL,
      10,
      95.0,
      @model.exploratory_interval(),
    )
    is Err(BootstrapError::NonFiniteSample(0)),
  )
  assert_true(
    compare_paired_with_bootstrap(
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
    is Err(BootstrapError::MismatchedPairs(2, 1)),
  )
}

///|
test "summaries and paired decisions cover neutral and directional cases" {
  let empty = summarize([])
  @test.assert_eq(empty.count, 0)
  @test.assert_eq(empty.median, 0.0)
  let slower = compare_paired(
    "baseline",
    "candidate",
    [100.0, 100.0],
    [110.0, 111.0],
    5.0,
    @model.confirmatory_interval(),
  )
  let equivalent = compare_paired(
    "baseline",
    "candidate",
    [100.0, 100.0],
    [101.0, 99.0],
    5.0,
    @model.confirmatory_interval(),
  )
  let unknown = compare_paired(
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
  assert_true(!is_faster(slower))
}

///|
test "outlier policies keep raw values isolated" {
  let values = [1.0, 1.0, 1.0, 100.0]
  assert_true(
    filter_outliers(values, @model.OutlierPolicy::ReportOnly) == values,
  )
  assert_true(
    filter_outliers(values, @model.OutlierPolicy::TukeyFence).length() <
    values.length(),
  )
  assert_true(
    filter_outliers(values, @model.OutlierPolicy::MADTrim).length() <
    values.length(),
  )
  assert_true(values == [1.0, 1.0, 1.0, 100.0])
}
