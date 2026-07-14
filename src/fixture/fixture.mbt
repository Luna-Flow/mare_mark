///|
pub struct SampleContext {
  sample_id : Int
  implementation_id : String
  repetition_id : Int
}

///|
pub fn SampleContext::new(
  sample_id : Int,
  implementation_id : String,
  repetition_id : Int,
) -> SampleContext {
  { sample_id, implementation_id, repetition_id }
}

///|
pub struct ResetContext {
  sample_id : Int
  implementation_id : String
}

///|
pub fn ResetContext::new(
  sample_id : Int,
  implementation_id : String,
) -> ResetContext {
  { sample_id, implementation_id }
}

///|
pub struct Fixture[Scale, Input, Prepared] {
  id : String
  version : String
  materialize : (@model.GenerationContext[Scale]) -> Input
  fingerprint : (Input) -> String
  clone_input : (Input) -> Input
  prepare : (Input, String, SampleContext) -> Prepared
  reset : (Prepared, ResetContext) -> Unit
  setup_policy : @model.SetupPolicy
}

///|
pub fn[Scale, Input, Prepared] Fixture::new(
  id : String,
  version : String,
  materialize : (@model.GenerationContext[Scale]) -> Input,
  fingerprint : (Input) -> String,
  clone_input : (Input) -> Input,
  prepare : (Input, String, SampleContext) -> Prepared,
  reset : (Prepared, ResetContext) -> Unit,
  setup_policy : @model.SetupPolicy,
) -> Fixture[Scale, Input, Prepared] {
  {
    id,
    version,
    materialize,
    fingerprint,
    clone_input,
    prepare,
    reset,
    setup_policy,
  }
}

///|
pub fn[Scale, Input, Prepared] materialize(
  fixture : Fixture[Scale, Input, Prepared],
  context : @model.GenerationContext[Scale],
) -> Input {
  (fixture.materialize)(context)
}

///|
pub fn[Scale, Input, Prepared] prepare(
  fixture : Fixture[Scale, Input, Prepared],
  input : Input,
  implementation_id : String,
  sample : SampleContext,
) -> Prepared {
  (fixture.prepare)(input, implementation_id, sample)
}
