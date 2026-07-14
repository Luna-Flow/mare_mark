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
test "consumer can construct a complete differential case" {
  let fixture : @fixture.Fixture[Int, Int, Int] = @fixture.Fixture::new(
    "integers",
    "1",
    context => context.dataset_key.scale,
    value => value.to_string(),
    value => value,
    (value, _, _) => value,
    (_, _) => (),
    @model.SetupPolicy::new(
      @model.SetupFrequency::PerSample,
      @model.SetupTiming::ExcludedFromMeasurement,
      @model.WorkspaceScope::SampleWorkspace,
    ),
  )
  let implementation : @runner.Implementation[Int, Int, Int] = @runner.Implementation::in_process(
    "candidate",
    "1",
    () => 0,
    (value, context) => {
      @model.OperationResult::completed(value + context, context + 1)
    },
  )
  let oracle : @experiment.ReferenceOracle[Int, Int, Int, Int] = @experiment.ReferenceOracle::new(
    "reference",
    () => 0,
    _ => 1,
    (value, _, context) => {
      @model.OperationResult::completed(value + context, context + 1)
    },
    (_, _, expected, actual) => {
      match (expected, actual) {
        (
          @model.ExecutionOutcome::Value(left),
          @model.ExecutionOutcome::Value(right),
        ) =>
          if left == right {
            @model.ValidationStatus::Valid
          } else {
            @model.ValidationStatus::Invalid("value mismatch")
          }
        _ => @model.ValidationStatus::Invalid("outcome mismatch")
      }
    },
    value => value.to_string(),
  )
  let differential_case : @runner.DifferentialCase[
    Int,
    Int,
    Int,
    Int,
    Int,
    Int,
    Int,
    Int,
  ] = @runner.DifferentialCase::new(
    "public-case",
    fixture,
    [implementation],
    @runner.OutputSink::new(() => 0, (sum, value) => sum + value, value => value),
    @experiment.OracleSpec::Reference(oracle),
    [4],
    value => value.to_string(),
    _ => 1,
    (value, _) => {
      @model.CaseDescriptor::new("identity", [value.to_string()], "", "")
    },
    value => value.to_string(),
    value => value.to_string(),
    value => value.to_string(),
    (value, implementation_id) => {
      @model.ReplaySpec::new("mare-mark", [
        "replay",
        implementation_id,
        value.to_string(),
      ])
    },
  )
  let built = @tune.BuiltCandidate::new(
    "scalar", implementation, "scalar-kernel",
  )
  @test.assert_eq(differential_case.id, "public-case")
  @test.assert_eq(built.kernel_id, "scalar-kernel")
}
