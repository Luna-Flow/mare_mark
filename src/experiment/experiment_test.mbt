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

///|
test "reference equality distinguishes value and outcome mismatches" {
  let oracle = ReferenceOracle::equal("identity", value => value, (
    expected,
    actual,
  ) => expected == actual)
  let valid = validate_reference(
    oracle,
    4,
    0,
    @model.ExecutionOutcome::Value(4),
    @model.ExecutionOutcome::Value(4),
    "candidate",
    "4",
  )
  let invalid = validate_reference(
    oracle,
    4,
    0,
    @model.ExecutionOutcome::Value(4),
    @model.ExecutionOutcome::Value(5),
    "candidate",
    "4",
  )
  let outcome_invalid = validate_reference(
    oracle,
    4,
    0,
    @model.ExecutionOutcome::Value(4),
    @model.ExecutionOutcome::Timeout(10, "slow"),
    "candidate",
    "4",
  )
  assert_true(valid.status is @model.ValidationStatus::Valid)
  assert_true(invalid.status is @model.ValidationStatus::Invalid(_))
  assert_true(outcome_invalid.status is @model.ValidationStatus::Invalid(_))
}

///|
test "crossover classifies inconclusive, stable, and found domains" {
  let domain = ScaleDomain::new([1, 2, 3, 4], (a, b) => a.compare(b), value => {
    value.to_string()
  })
  assert_true(
    crossover_from_labels(domain, ["A"])
    is @model.CrossoverResult::Inconclusive(_, _),
  )
  assert_true(
    crossover_from_labels(domain, ["A", "A", "A", "A"])
    is @model.CrossoverResult::NoCrossover(_, _),
  )
  assert_true(
    crossover_from_labels(domain, ["A", "Unknown", "B", "B"])
    is @model.CrossoverResult::NoCrossover(_, _),
  )
  assert_true(
    crossover_from_labels(domain, ["A", "A", "B", "B"])
    is @model.CrossoverResult::Found(_, _, _),
  )
  assert_true(comparator_label(-6.0, 5.0) == "A")
  assert_true(comparator_label(6.0, 5.0) == "B")
  assert_true(comparator_label(1.0, 5.0) == "Unknown")
}
