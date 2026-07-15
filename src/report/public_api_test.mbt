///|
test "consumer can construct public configuration models" {
  let measurement = @model.MeasurementKey::new(1, 2, 3)
  let generator : @generator.Generator[Int, String] = @generator.Generator::new(
    "strings",
    "1",
    context => context.seed.to_string(),
    @generator.stable_fingerprint,
  )
  let region = @model.Region::new(None, Some(16), "scalar", ["sample-1"])
  let _policy : @model.DeploymentPolicy[Int, String] = @model.DeploymentPolicy::Piecewise([
      region,
    ],
  )
  let holdout : @tune.HoldoutPlan[Int] = @tune.HoldoutPlan::MeasurementHoldout(
    3,
  )
  let budget = @tune.TuningBudget::new(32, 256, None, 3, 10, 4, holdout)
  let objective = @tune.TuningObjective::new(1.0, Some(1024UL), true)
  let score = @tune.CandidateScore::new("scalar", 1.0, 64.0, true)
  let _candidate = @tune_gemm.GemmCandidate::new(
    64,
    64,
    32,
    4,
    4,
    @tune_gemm.Packing::AB,
    "blocked",
    "scalar",
    @tune_gemm.AllocationMode::FreshPerOperation,
    @tune_gemm.TimingScope::EndToEnd,
  )
  @test.assert_eq(measurement.dataset_id, 1)
  @test.assert_eq(generator.id, "strings")
  @test.assert_eq(budget.max_candidates, 32)
  @test.assert_eq(objective.minimize_secondary, true)
  @test.assert_eq(score.candidate_id, "scalar")
}

///|
test "consumer can compile an immutable benchmark description" {
  let implementation : @runner.Implementation[Int, Int, Unit] = @runner.Implementation::stateless(
    "candidate",
    "1",
    value => @model.OperationResult::completed(value, ()),
  )
  let plan = @runner.single_step("public-case", [4])
    .with_immutable_input(context => context.dataset_key.scale, value => {
      value.to_string()
    })
    .compare([implementation])
    .against_equal(value => value, (expected, actual) => expected == actual)
    .compile()
  let built = @tune.BuiltCandidate::new(
    "scalar", implementation, "scalar-kernel",
  )
  assert_true(plan is Ok(_))
  @test.assert_eq(built.kernel_id, "scalar-kernel")
}
