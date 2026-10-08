///|
test "crossover rejects multiple transitions" {
  let domain = @experiment.ScaleDomain::new(
    [1, 2, 3, 4],
    (left, right) => left - right,
    value => value.to_string(),
  )
  let result = @experiment.crossover_from_labels(domain, ["A", "B", "A", "B"])
  match result {
    @model.CrossoverResult::NonMonotonic(_) => ()
    _ => @test.fail("expected non-monotonic result")
  }
}

///|
test "shrinker keeps only failure-preserving reductions" {
  let shrinker = @experiment.Shrinker::new(
    value => if value <= 1 { [] } else { [value / 2, value - 1] },
    value => value.to_string(),
    max_steps=32,
  )
  let (minimal, path) = @experiment.shrink(100, shrinker, value => value >= 7)
  assert_eq(minimal, 7)
  assert_true(path.length() > 0)
}

///|
test "reference equality distinguishes value and outcome mismatches" {
  let oracle = @experiment.ReferenceOracle::equal("identity", value => value, (
    expected,
    actual,
  ) => expected == actual)
  let valid = @experiment.validate_reference(
    oracle,
    4,
    0,
    @model.ExecutionOutcome::Value(4),
    @model.ExecutionOutcome::Value(4),
    "candidate",
    "4",
  )
  let invalid = @experiment.validate_reference(
    oracle,
    4,
    0,
    @model.ExecutionOutcome::Value(4),
    @model.ExecutionOutcome::Value(5),
    "candidate",
    "4",
  )
  let outcome_invalid = @experiment.validate_reference(
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
  let domain = @experiment.ScaleDomain::new(
    [1, 2, 3, 4],
    (a, b) => a.compare(b),
    value => value.to_string(),
  )
  assert_true(
    @experiment.crossover_from_labels(domain, ["A"])
    is @model.CrossoverResult::Inconclusive(_, _),
  )
  assert_true(
    @experiment.crossover_from_labels(domain, ["A", "A", "A", "A"])
    is @model.CrossoverResult::NoCrossover(_, _),
  )
  assert_true(
    @experiment.crossover_from_labels(domain, ["A", "Unknown", "B", "B"])
    is @model.CrossoverResult::NoCrossover(_, _),
  )
  assert_true(
    @experiment.crossover_from_labels(domain, ["A", "A", "B", "B"])
    is @model.CrossoverResult::Found(_, _, _),
  )
  assert_true(@experiment.comparator_label(-6.0, 5.0) == "A")
  assert_true(@experiment.comparator_label(6.0, 5.0) == "B")
  assert_true(@experiment.comparator_label(1.0, 5.0) == "Unknown")
}

///|
test "comparator_label leaves ties and unusable thresholds unlabelled" {
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  assert_true(@experiment.comparator_label(0.0, 0.0) == "Unknown")
  assert_true(@experiment.comparator_label(-1.0, 0.0) == "A")
  assert_true(@experiment.comparator_label(1.0, 0.0) == "B")
  assert_true(@experiment.comparator_label(-50.0, nan) == "Unknown")
  assert_true(@experiment.comparator_label(-50.0, inf) == "Unknown")
  assert_true(@experiment.comparator_label(3.0, -5.0) == "Unknown")
  assert_true(@experiment.comparator_label(nan, 5.0) == "Unknown")
}

///|
test "crossover sorts the domain with its comparator" {
  let unsorted = @experiment.ScaleDomain::new(
    [64, 16, 256],
    (a, b) => a.compare(b),
    value => value.to_string(),
  )
  match @experiment.crossover_from_labels(unsorted, ["B", "A", "B"]) {
    Found(boundary, _, evidence) => {
      assert_eq(boundary.below, 16)
      assert_eq(boundary.at_or_above, 64)
      assert_eq(evidence, ["A", "B", "B"])
    }
    _ => fail("expected a crossover")
  }
  let descending = @experiment.ScaleDomain::new(
    [256, 64, 16],
    (a, b) => b.compare(a),
    value => value.to_string(),
  )
  match @experiment.crossover_from_labels(descending, ["B", "B", "A"]) {
    Found(boundary, _, _) => {
      assert_eq(boundary.below, 64)
      assert_eq(boundary.at_or_above, 16)
    }
    _ => fail("expected a crossover")
  }
}
