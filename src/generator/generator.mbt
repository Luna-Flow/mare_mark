///|
pub struct Generator[Scale, Input] {
  id : String
  version : String
  generate : (@model.GenerationContext[Scale]) -> Input
  fingerprint : (Input) -> String
}

///|
pub fn[Scale, Input] Generator::new(
  id : String,
  version : String,
  generate : (@model.GenerationContext[Scale]) -> Input,
  fingerprint : (Input) -> String,
) -> Generator[Scale, Input] {
  { id, version, generate, fingerprint }
}

///|
pub fn derive_seed(seed : UInt64, domain : String, index : Int) -> UInt64 {
  let mut mixed = seed ^ 0xCBF29CE484222325
  for character in domain {
    mixed = (mixed ^ character.to_int().to_uint64()) * 0x100000001B3
  }
  mixed = (mixed ^ index.to_uint64()) * 0x9E3779B97F4A7C15
  mixed = (mixed ^ (mixed >> 30)) * 0xBF58476D1CE4E5B9
  mixed = (mixed ^ (mixed >> 27)) * 0x94D049BB133111EB
  mixed ^ (mixed >> 31)
}

///|
pub fn measurement_seed(
  seed : UInt64,
  dataset_id : Int,
  repetition_id : Int,
  block_id : Int,
) -> UInt64 {
  derive_seed(
    derive_seed(
      derive_seed(seed, "dataset", dataset_id),
      "repetition",
      repetition_id,
    ),
    "block",
    block_id,
  )
}

///|
pub fn stable_fingerprint(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
pub fn[Scale] context(
  seed : UInt64,
  suite_id : String,
  case_id : String,
  dataset_key : @model.DatasetKey[Scale],
  generator_id : String,
  generator_version : String,
) -> @model.GenerationContext[Scale] {
  @model.GenerationContext::new(
    seed, suite_id, case_id, dataset_key, generator_id, generator_version,
  )
}
