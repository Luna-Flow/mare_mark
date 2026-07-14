///|
test "seed domains and fingerprints use content" {
  assert_true(derive_seed(1, "ab", 0) != derive_seed(1, "cd", 0))
  assert_true(stable_fingerprint("ab") != stable_fingerprint("cd"))
  assert_eq(stable_fingerprint("decimal"), stable_fingerprint("decimal"))
  assert_true(stable_fingerprint("decimal").has_prefix("sha256:"))
}
