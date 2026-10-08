///|
test "sample scoring uses the median of usable measurements" {
  let score = @tune.score_samples(
    "candidate",
    [9.0, @double.not_a_number, 1.0, -1.0, 5.0, @double.infinity],
    32.0,
  )
  @test.assert_eq(score.valid, true)
  @test.assert_eq(score.primary, 5.0)
  @test.assert_eq(@tune.score_samples("invalid", [], 1.0).valid, false)
  @test.assert_eq(@tune.score_samples("invalid", [1.0], -1.0).valid, false)
}

///|
test "pareto frontier removes dominated and invalid scores" {
  let frontier = @tune.pareto_frontier([
    @tune.CandidateScore::new("dominated", 3.0, 3.0, true),
    @tune.CandidateScore::new("memory", 2.0, 1.0, true),
    @tune.CandidateScore::new("speed", 1.0, 2.0, true),
    @tune.CandidateScore::new("invalid", 0.0, 0.0, false),
  ])
  @test.assert_eq(frontier.length(), 2)
  @test.assert_eq(frontier[0].candidate_id, "speed")
  @test.assert_eq(frontier[1].candidate_id, "memory")
}

///|
test "best selection is order independent and bounded by fastest score" {
  let scores = [
    @tune.CandidateScore::new("fastest", 100.0, 100.0, true),
    @tune.CandidateScore::new("balanced", 104.0, 10.0, true),
    @tune.CandidateScore::new("too-slow", 108.0, 1.0, true),
    @tune.CandidateScore::new("invalid", 1.0, 0.0, false),
  ]
  let reversed = [scores[2], scores[1], scores[0], scores[3]]
  match
    (
      @tune.select_best(scores, 5.0, true),
      @tune.select_best(reversed, 5.0, true),
    ) {
    (Some(left), Some(right)) => {
      @test.assert_eq(left.candidate_id, "balanced")
      @test.assert_eq(right.candidate_id, "balanced")
    }
    _ => @test.assert_eq(true, false)
  }
}

///|
test "seeded order and confirmation count are deterministic" {
  let first = @tune.seeded_order(["a", "b", "c", "d"], 42UL, value => value)
  let second = @tune.seeded_order(["d", "c", "b", "a"], 42UL, value => value)
  @test.assert_eq(first, second)
  @test.assert_eq(@tune.confirmation_count(4, 0.0, 20), 4)
  @test.assert_eq(@tune.confirmation_count(4, 0.1, 20), 8)
  @test.assert_eq(@tune.confirmation_count(4, 0.3, 10), 10)
}

///|
test "exhaustive scoring rejects non-finite measurements" {
  let space = @tune.CandidateSpace::new(
    () => ["bad", "good"],
    value => value,
    _ => true,
    _ => [],
  )
  let result = @tune.exhaustive_scores(space, 2, candidate => {
    if candidate == "bad" {
      @tune.CandidateScore::new(candidate, @double.not_a_number, 0.0, true)
    } else {
      @tune.CandidateScore::new(candidate, 2.0, 0.0, true)
    }
  })
  @test.assert_eq(result.build_events[0].accepted, false)
  @test.assert_eq(result.build_events[0].reason, "measurement")
  @test.assert_eq(result.policy, "global:good")
}

///|
test "seeded order separates ids that differ only at the end" {
  let ids = Array::makei(100, index => "candidate-" + index.to_string())
  let decade : Map[String, Int] = Map([])
  for index, id in ids {
    decade[id] = index / 10
  }
  for seed in [1UL, 2UL, 2026UL] {
    let order = @tune.seeded_order(ids, seed, id => id)
    assert_eq(order.length(), 100)
    // Unmixed FNV-1a keys put one block of ten consecutive ids first.
    let first = decade.get(order[0]).unwrap()
    assert_true(order[:10].iter().any(id => decade.get(id).unwrap() != first))
  }
}

///|
test "seeded order is a permutation that changes with the seed" {
  let ids = Array::makei(64, index => "c" + index.to_string())
  let first = @tune.seeded_order(ids, 1UL, id => id)
  let second = @tune.seeded_order(ids, 2UL, id => id)
  let sorted = first.copy()
  sorted.sort()
  let expected = ids.copy()
  expected.sort()
  assert_eq(sorted, expected)
  assert_true(first != second)
}
