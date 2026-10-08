///|
test "gemm boundary sampler and candidate constraints" {
  let shape = @tune_gemm.GemmScale::new(
    64,
    64,
    64,
    1,
    8,
    @tune_gemm.row_major(),
    @tune_gemm.row_major(),
    @tune_gemm.row_major(),
  )
  @test.assert_eq(@tune_gemm.boundary_shapes(shape).length(), 3)
  let candidate = @tune_gemm.GemmCandidate::new(
    64,
    64,
    32,
    4,
    4,
    @tune_gemm.pack_ab(),
    "m_n_k",
    "scalar",
    @tune_gemm.reusable_workspace(),
    @tune_gemm.compute_only(),
  )
  @test.assert_eq(@tune_gemm.valid_candidate(candidate, 1024UL * 1024UL), true)
}

///|
test "blocked gemm matches reference across layouts and tails" {
  let layouts = [@tune_gemm.row_major(), @tune_gemm.column_major()]
  let candidate = @tune_gemm.GemmCandidate::new(
    2,
    3,
    1,
    2,
    2,
    @tune_gemm.pack_ab(),
    "m_n_k",
    "scalar",
    @tune_gemm.reusable_workspace(),
    @tune_gemm.compute_only(),
  )
  for layout_a in layouts {
    for layout_b in layouts {
      for layout_c in layouts {
        let shape = @tune_gemm.GemmScale::new(
          3, 5, 2, 1, 1, layout_a, layout_b, layout_c,
        )
        let a = @tune_gemm.reproducible_matrix(7UL, shape.m, shape.k, layout_a)
        let b = @tune_gemm.reproducible_matrix(11UL, shape.k, shape.n, layout_b)
        @test.assert_eq(
          @tune_gemm.gemm_is_correct(
            shape, a, b, candidate, 0.000000000001, 4096UL,
          ),
          true,
        )
      }
    }
  }
}

///|
test "gemm rejects unsupported candidates and invalid batches" {
  let unsupported = @tune_gemm.GemmCandidate::new(
    4,
    4,
    4,
    2,
    2,
    @tune_gemm.pack_ab(),
    "blocked",
    "scalar",
    @tune_gemm.reusable_workspace(),
    @tune_gemm.compute_only(),
  )
  @test.assert_eq(@tune_gemm.valid_candidate(unsupported, 4096UL), false)
  let invalid_shape = @tune_gemm.GemmScale::new(
    2,
    2,
    2,
    -1,
    1,
    @tune_gemm.row_major(),
    @tune_gemm.row_major(),
    @tune_gemm.row_major(),
  )
  @test.assert_eq(@tune_gemm.gemm_reference(invalid_shape, [], []).length(), 0)
  @test.assert_eq(
    @tune_gemm.gemm_blocked(invalid_shape, [], [], unsupported).length(),
    0,
  )
  @test.assert_eq(@tune_gemm.pack_operand(invalid_shape, [], "a").length(), 0)
}

///|
test "candidate enumeration and config serialization are deterministic" {
  let candidates = @tune_gemm.enumerate_gemm_candidates()
  @test.assert_eq(candidates.length(), 486)
  @test.assert_eq(
    candidates.all(candidate => @tune_gemm.valid_candidate(candidate, 262144UL)),
    true,
  )
  let shape = @tune_gemm.GemmScale::new(
    3,
    5,
    2,
    1,
    1,
    @tune_gemm.row_major(),
    @tune_gemm.column_major(),
    @tune_gemm.row_major(),
  )
  let config = @tune_gemm.GemmTuningConfig::new(
    18446744073709551615UL,
    [shape],
    [
      @tune_gemm.GemmCandidate::new(
        4,
        4,
        4,
        2,
        2,
        @tune_gemm.pack_ab(),
        "m_\n_n_k",
        "scalar",
        @tune_gemm.reusable_workspace(),
        @tune_gemm.compute_only(),
      ),
    ],
    18446744073709551615UL,
    3,
    7,
  )
  let encoded = @tune_gemm.config_json(config)
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
  let baseline = @tune_gemm.GemmEnvironment::new(
    "native", "0.9.2", "-O3", "f64", "native", "cpu-a", "default", 1, "monotonic",
  )
  let same = @tune_gemm.GemmEnvironment::new(
    "native", "0.9.2", "-O3", "f64", "native", "cpu-a", "default", 1, "monotonic",
  )
  let different = @tune_gemm.GemmEnvironment::new(
    "native", "0.9.2", "-O3", "f64", "native", "cpu-b", "default", 1, "monotonic",
  )
  @test.assert_eq(@tune_gemm.environment_compatible(baseline, same), true)
  @test.assert_eq(@tune_gemm.environment_compatible(baseline, different), false)
}

///|
test "gemm validation rejects non-finite and tolerance errors" {
  let invalid_tolerance = @tune_gemm.validate_gemm([1.0], [1.0], -1.0)
  @test.assert_eq(invalid_tolerance.valid, false)
  @test.assert_eq(invalid_tolerance.mismatches, 1)
  let mismatch = @tune_gemm.validate_gemm([1.0, 2.0], [1.0], 0.0)
  @test.assert_eq(mismatch.valid, false)
  @test.assert_eq(mismatch.mismatches, 1)
  let non_finite = @tune_gemm.validate_gemm([1.0 / 0.0], [1.0], 0.1)
  @test.assert_eq(non_finite.valid, false)
  @test.assert_eq(non_finite.mismatches, 1)
}

///|
test "gemm supports unpacked operands and rejects invalid candidates" {
  let shape = @tune_gemm.GemmScale::new(
    2,
    2,
    2,
    1,
    1,
    @tune_gemm.row_major(),
    @tune_gemm.row_major(),
    @tune_gemm.row_major(),
  )
  let candidate = @tune_gemm.GemmCandidate::new(
    2,
    2,
    1,
    1,
    1,
    @tune_gemm.Packing::None,
    "m_n_k",
    "scalar",
    @tune_gemm.reusable_workspace(),
    @tune_gemm.compute_only(),
  )
  let a = @tune_gemm.reproducible_matrix(1UL, 2, 2, @tune_gemm.row_major())
  let b = @tune_gemm.reproducible_matrix(2UL, 2, 2, @tune_gemm.row_major())
  @test.assert_eq(
    @tune_gemm.gemm_is_correct(shape, a, b, candidate, 0.0000001, 4096UL),
    true,
  )
  let invalid = @tune_gemm.execute_candidate(shape, a, [0.0], candidate, 4096UL)
  @test.assert_eq(invalid, None)
}
