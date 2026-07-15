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
    "m_n_k",
    "scalar",
    reusable_workspace(),
    compute_only(),
  )
  @test.assert_eq(valid_candidate(candidate, 1024UL * 1024UL), true)
}

///|
test "blocked gemm matches reference across layouts and tails" {
  let layouts = [row_major(), column_major()]
  let candidate = GemmCandidate::new(
    2,
    3,
    1,
    2,
    2,
    pack_ab(),
    "m_n_k",
    "scalar",
    reusable_workspace(),
    compute_only(),
  )
  for layout_a in layouts {
    for layout_b in layouts {
      for layout_c in layouts {
        let shape = GemmScale::new(3, 5, 2, 1, 1, layout_a, layout_b, layout_c)
        let a = reproducible_matrix(7UL, shape.m, shape.k, layout_a)
        let b = reproducible_matrix(11UL, shape.k, shape.n, layout_b)
        @test.assert_eq(
          gemm_is_correct(shape, a, b, candidate, 0.000000000001, 4096UL),
          true,
        )
      }
    }
  }
}

///|
test "gemm rejects unsupported candidates and invalid batches" {
  let unsupported = GemmCandidate::new(
    4,
    4,
    4,
    2,
    2,
    pack_ab(),
    "blocked",
    "scalar",
    reusable_workspace(),
    compute_only(),
  )
  @test.assert_eq(valid_candidate(unsupported, 4096UL), false)
  let invalid_shape = GemmScale::new(
    2,
    2,
    2,
    -1,
    1,
    row_major(),
    row_major(),
    row_major(),
  )
  @test.assert_eq(gemm_reference(invalid_shape, [], []).length(), 0)
  @test.assert_eq(gemm_blocked(invalid_shape, [], [], unsupported).length(), 0)
  @test.assert_eq(pack_operand(invalid_shape, [], "a").length(), 0)
}

///|
test "candidate enumeration and config serialization are deterministic" {
  let candidates = enumerate_gemm_candidates()
  @test.assert_eq(candidates.length(), 486)
  @test.assert_eq(
    candidates.all(candidate => valid_candidate(candidate, 262144UL)),
    true,
  )
  let shape = GemmScale::new(
    3,
    5,
    2,
    1,
    1,
    row_major(),
    column_major(),
    row_major(),
  )
  let config = GemmTuningConfig::new(
    18446744073709551615UL,
    [shape],
    [
      GemmCandidate::new(
        4,
        4,
        4,
        2,
        2,
        pack_ab(),
        "m_\n_n_k",
        "scalar",
        reusable_workspace(),
        compute_only(),
      ),
    ],
    18446744073709551615UL,
    3,
    7,
  )
  let encoded = config_json(config)
  ignore(@json.parse(encoded))
  @test.assert_eq(encoded.contains("\"schema_version\":\"mmkts_1\""), true)
  @test.assert_eq(
    config.schema_version.lifecycle() is @model.VersionLifecycle::Supported,
    true,
  )
  @test.assert_eq(encoded.contains("\"seed\":\"18446744073709551615\""), true)
  @test.assert_eq(encoded.contains("m_\\n_n_k"), true)
}

///|
test "environment compatibility checks performance fields" {
  let baseline = GemmEnvironment::new(
    "native", "0.9.2", "-O3", "f64", "native", "cpu-a", "default", 1, "monotonic",
  )
  let same = GemmEnvironment::new(
    "native", "0.9.2", "-O3", "f64", "native", "cpu-a", "default", 1, "monotonic",
  )
  let different = GemmEnvironment::new(
    "native", "0.9.2", "-O3", "f64", "native", "cpu-b", "default", 1, "monotonic",
  )
  @test.assert_eq(environment_compatible(baseline, same), true)
  @test.assert_eq(environment_compatible(baseline, different), false)
}

///|
test "gemm validation rejects non-finite and tolerance errors" {
  let invalid_tolerance = validate_gemm([1.0], [1.0], -1.0)
  @test.assert_eq(invalid_tolerance.valid, false)
  @test.assert_eq(invalid_tolerance.mismatches, 1)
  let mismatch = validate_gemm([1.0, 2.0], [1.0], 0.0)
  @test.assert_eq(mismatch.valid, false)
  @test.assert_eq(mismatch.mismatches, 1)
  let non_finite = validate_gemm([1.0 / 0.0], [1.0], 0.1)
  @test.assert_eq(non_finite.valid, false)
  @test.assert_eq(non_finite.mismatches, 1)
}

///|
test "gemm supports unpacked operands and rejects invalid candidates" {
  let shape = GemmScale::new(
    2,
    2,
    2,
    1,
    1,
    row_major(),
    row_major(),
    row_major(),
  )
  let candidate = GemmCandidate::new(
    2,
    2,
    1,
    1,
    1,
    Packing::None,
    "m_n_k",
    "scalar",
    reusable_workspace(),
    compute_only(),
  )
  let a = reproducible_matrix(1UL, 2, 2, row_major())
  let b = reproducible_matrix(2UL, 2, 2, row_major())
  @test.assert_eq(
    gemm_is_correct(shape, a, b, candidate, 0.0000001, 4096UL),
    true,
  )
  let invalid = execute_candidate(shape, a, [0.0], candidate, 4096UL)
  @test.assert_eq(invalid, None)
}
