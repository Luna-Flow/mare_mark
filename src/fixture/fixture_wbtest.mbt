///|
test "immutable fixtures preserve materialization and setup policy" {
  let fixture : Fixture[Int, Int, Int] = Fixture::immutable(
    "integers",
    "1",
    context => context.dataset_key.scale + context.dataset_key.dataset_id,
    value => "fp:" + value.to_string(),
  )
  let generation = @model.GenerationContext::new(
    7UL,
    "suite",
    "case",
    @model.DatasetKey::new(10, 2),
    fixture.id,
    fixture.version,
  )
  assert_eq(materialize(fixture, generation), 12)
  assert_eq((fixture.fingerprint)(12), "fp:12")
  let prepared = prepare(
    fixture,
    12,
    "candidate",
    SampleContext::new(4, "candidate", 1),
  )
  assert_eq(prepared, 12)
  assert_true(
    fixture.setup_policy.frequency is @model.SetupFrequency::PerDataset,
  )
  assert_true(
    fixture.setup_policy.timing is @model.SetupTiming::ExcludedFromMeasurement,
  )
  assert_true(
    fixture.setup_policy.workspace_scope
    is @model.WorkspaceScope::DatasetWorkspace,
  )
}

///|
test "sample and reset contexts remain implementation scoped" {
  let sample = SampleContext::new(3, "candidate", 8)
  let reset = ResetContext::new(3, "candidate")
  assert_eq(sample.sample_id, 3)
  assert_eq(sample.implementation_id, "candidate")
  assert_eq(sample.repetition_id, 8)
  assert_eq(reset.sample_id, 3)
  assert_eq(reset.implementation_id, "candidate")
}
