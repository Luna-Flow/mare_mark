///|
test "seed domains and fingerprints use content" {
  assert_true(derive_seed(1, "ab", 0) != derive_seed(1, "cd", 0))
  assert_true(stable_fingerprint("ab") != stable_fingerprint("cd"))
  assert_eq(stable_fingerprint("decimal"), stable_fingerprint("decimal"))
  assert_true(stable_fingerprint("decimal").has_prefix("sha256:"))
}

///|
test "measurement seeds are domain separated and context keeps metadata" {
  let dataset = measurement_seed(99UL, 1, 0, 0)
  let repetition = measurement_seed(99UL, 1, 1, 0)
  let block = measurement_seed(99UL, 1, 0, 1)
  assert_true(dataset != repetition)
  assert_true(dataset != block)
  let context = context(
    42UL,
    "suite",
    "case",
    @model.DatasetKey::new(16, 3),
    "generator",
    "2",
  )
  assert_eq(context.seed, 42UL)
  assert_eq(context.suite_id, "suite")
  assert_eq(context.case_id, "case")
  assert_eq(context.generator_id, "generator")
  assert_eq(context.generator_version, "2")
  assert_eq(context.dataset_key.dataset_id, 3)
}
