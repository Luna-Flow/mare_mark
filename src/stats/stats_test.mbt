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
