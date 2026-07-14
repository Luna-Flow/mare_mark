///|
test "crossover rejects multiple transitions" {
  let domain = ScaleDomain::new([1, 2, 3, 4], (left, right) => left - right, value => {
    value.to_string()
  })
  let result = crossover_from_labels(domain, ["A", "B", "A", "B"])
  match result {
    @model.CrossoverResult::NonMonotonic(_) => ()
    _ => @test.fail("expected non-monotonic result")
  }
}

///|
test "shrinker keeps only failure-preserving reductions" {
  let shrinker = Shrinker::new(
    value => if value <= 1 { [] } else { [value / 2, value - 1] },
    value => value.to_string(),
    max_steps=32,
  )
  let (minimal, path) = shrink(100, shrinker, value => value >= 7)
  assert_eq(minimal, 7)
  assert_true(path.length() > 0)
}
