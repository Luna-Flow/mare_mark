///|
test "gemm boundary sampler and candidate constraints" {
  let shape = GemmScale::new(
    64,
    64,
    64,
    1,
    8,
    row_major(),
    row_major(),
    row_major(),
  )
  @test.assert_eq(boundary_shapes(shape).length(), 3)
  let candidate = GemmCandidate::new(
    64,
    64,
    32,
    4,
    4,
    pack_ab(),
    "blocked",
    "scalar",
    reusable_workspace(),
    compute_only(),
  )
  @test.assert_eq(valid_candidate(candidate, 1024UL * 1024UL), true)
}
