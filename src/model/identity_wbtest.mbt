///|
fn identity_base_protocol() -> RunProtocol {
  RunProtocol::new(
    FixedDatasetRepeatedMeasurements,
    1,
    None,
    CalibrationProtocol::new(1000.0, 1, 1000, 100000.0, PerImplementation),
    2.0,
    BalancedBlocks(42UL),
    ReportOnly,
    EveryMeasurement,
    0,
    5,
  )
}

///|
/// The base protocol with exactly one field changed, for every field.
fn identity_single_field_variants() -> Array[(String, RunProtocol)] {
  let base = identity_base_protocol()
  let cal = base.calibration
  [
    (
      "experiment_design",
      { ..base, experiment_design: HierarchicalDatasetsAndRepeats, },
    ),
    ("warmup_iterations", { ..base, warmup_iterations: 2, }),
    ("warmup_time_us none->some", { ..base, warmup_time_us: Some(0.0), }),
    (
      "calibration.target_batch_time_us",
      { ..base, calibration: { ..cal, target_batch_time_us: 1000.5, }, },
    ),
    (
      "calibration.min_batch_iterations",
      { ..base, calibration: { ..cal, min_batch_iterations: 2, }, },
    ),
    (
      "calibration.max_batch_iterations",
      { ..base, calibration: { ..cal, max_batch_iterations: 1001, }, },
    ),
    (
      "calibration.max_sample_time_us",
      { ..base, calibration: { ..cal, max_sample_time_us: 99999.0, }, },
    ),
    (
      "calibration.batch_policy",
      { ..base, calibration: { ..cal, batch_policy: SharedBatchSize, }, },
    ),
    ("practical_delta_pct", { ..base, practical_delta_pct: 2.5, }),
    ("order_policy kind", { ..base, order_policy: FixedOrder, }),
    ("order_policy seed", { ..base, order_policy: BalancedBlocks(43UL), }),
    ("outlier_policy", { ..base, outlier_policy: MADTrim, }),
    ("validation_coverage", { ..base, validation_coverage: ConfirmatoryOnly, }),
    ("exploratory_samples", { ..base, exploratory_samples: 1, }),
    ("confirmatory_samples", { ..base, confirmatory_samples: 6, }),
    ("repeats_per_dataset", { ..base, repeats_per_dataset: 5, }),
  ]
}

///|
test "issue #3 reproduction: protocols differing outside three fields differ" {
  let cal = CalibrationProtocol::new(
    1000.0,
    1,
    1000,
    100000.0,
    PerImplementation,
  )
  let p1 = RunProtocol::new(
    FixedDatasetRepeatedMeasurements,
    1,
    None,
    cal,
    2.0,
    FixedOrder,
    ReportOnly,
    EveryMeasurement,
    0,
    5,
  )
  let cal2 = CalibrationProtocol::new(50.0, 7, 9, 200.0, SharedBatchSize)
  let p2 = RunProtocol::new(
    HierarchicalDatasetsAndRepeats,
    1,
    Some(5000.0),
    cal2,
    2.0,
    BalancedBlocks(42UL),
    MADTrim,
    ConfirmatoryOnly,
    100,
    5,
  )
  assert_true(protocol_identity(p1) != protocol_identity(p2))
  assert_true(
    artifact_identity("case", "impl", 0, p1) !=
    artifact_identity("case", "impl", 0, p2),
  )
}

///|
test "changing any single protocol field changes the identity" {
  let base = identity_base_protocol()
  let base_identity = protocol_identity(base)
  let seen : Map[String, String] = Map([])
  seen[base_identity] = "base"
  for variant in identity_single_field_variants() {
    let (field, protocol) = variant
    let identity = protocol_identity(protocol)
    if identity == base_identity {
      fail("changing " + field + " did not change the identity")
    }
    if seen.get(identity) is Some(other) {
      fail(field + " and " + other + " share an identity")
    }
    seen[identity] = field
    assert_true(
      artifact_identity("case", "impl", 0, protocol) !=
      artifact_identity("case", "impl", 0, base),
    )
  }
}

///|
test "warm-up time value and sign of zero change the identity" {
  let base = identity_base_protocol()
  let some_zero = protocol_identity({ ..base, warmup_time_us: Some(0.0), })
  let some_neg_zero = protocol_identity({ ..base, warmup_time_us: Some(-0.0), })
  let some_five = protocol_identity({ ..base, warmup_time_us: Some(5000.0), })
  assert_true(some_zero != some_neg_zero)
  assert_true(some_zero != some_five)
  assert_true(protocol_identity(base) != some_five)
}

///|
test "equal protocols have equal identities" {
  let first = identity_base_protocol()
  let second = RunProtocol::new(
    FixedDatasetRepeatedMeasurements,
    1,
    None,
    CalibrationProtocol::new(1000.0, 1, 1000, 100000.0, PerImplementation),
    2.0,
    BalancedBlocks(42UL),
    ReportOnly,
    EveryMeasurement,
    0,
    5,
  )
  assert_eq(protocol_identity(first), protocol_identity(second))
  assert_eq(
    protocol_canonical_encoding(first),
    protocol_canonical_encoding(second),
  )
  assert_eq(
    artifact_identity("case", "impl", 3, first),
    artifact_identity("case", "impl", 3, second),
  )
}

///|
test "protocol identity is mmkp_2 and a 16-digit hex digest" {
  let protocol = identity_base_protocol()
  inspect(
    protocol_canonical_encoding(protocol),
    content=(
      #|mmkp_2;experiment_design=fixed_dataset_repeated_measurements;warmup_iterations=1;warmup_time_us=none;calibration.target_batch_time_us=0x408f400000000000;calibration.min_batch_iterations=1;calibration.max_batch_iterations=1000;calibration.max_sample_time_us=0x40f86a0000000000;calibration.batch_policy=per_implementation;practical_delta_pct=0x4000000000000000;order_policy=balanced_blocks(42);outlier_policy=report_only;validation_coverage=every_measurement;exploratory_samples=0;confirmatory_samples=5;repeats_per_dataset=1
    ),
  )
  let identity = protocol_identity(protocol)
  assert_eq(identity.length(), "mmkp_2:".length() + 16)
  assert_true(identity.has_prefix("mmkp_2:"))
  // Pins the digest so every backend computes the same identity.
  inspect(
    identity,
    content=(
      #|mmkp_2:32e7e1e2bd8ea771
    ),
  )
  inspect(
    protocol_canonical_encoding({
      ..protocol,
      warmup_time_us: Some(5000.0),
      order_policy: FixedOrder,
    }).contains(";warmup_time_us=some(0x40b3880000000000);"),
    content="true",
  )
}

///|
test "FNV-1a matches the published 64-bit test vectors" {
  assert_eq(fnv1a64(""), 0xCBF29CE484222325UL)
  assert_eq(fnv1a64("a"), 0xAF63DC4C8601EC8CUL)
  assert_eq(fnv1a64("foobar"), 0x85944171F73967E8UL)
  assert_eq(hex16(0UL), "0000000000000000")
  assert_eq(hex16(0xFEDCBA9876543210UL), "fedcba9876543210")
}

///|
fn identity_provenance(
  run_id : String,
  timestamp : String,
) -> ProvenanceEnvironment {
  ProvenanceEnvironment::new("os", "host", timestamp, "rev", run_id)
}

///|
test "run identity combines case, protocol, seed and provenance" {
  let protocol = identity_base_protocol()
  let base = run_identity(
    "case",
    protocol,
    7UL,
    identity_provenance("run-a", "2026-10-09T12:00:00Z"),
  )
  assert_eq(
    base,
    "case|" + protocol_identity(protocol) + "|7|run-a|2026-10-09T12:00:00Z",
  )
  let others = [
    run_identity(
      "other",
      protocol,
      7UL,
      identity_provenance("run-a", "2026-10-09T12:00:00Z"),
    ),
    run_identity(
      "case",
      { ..protocol, outlier_policy: TukeyFence, },
      7UL,
      identity_provenance("run-a", "2026-10-09T12:00:00Z"),
    ),
    run_identity(
      "case",
      protocol,
      8UL,
      identity_provenance("run-a", "2026-10-09T12:00:00Z"),
    ),
    run_identity(
      "case",
      protocol,
      7UL,
      identity_provenance("run-b", "2026-10-09T12:00:00Z"),
    ),
    run_identity(
      "case",
      protocol,
      7UL,
      identity_provenance("run-a", "2026-10-09T12:00:01Z"),
    ),
  ]
  for other in others {
    assert_true(other != base)
  }
}

///|
test "run identity escapes separators in free-text components" {
  let protocol = identity_base_protocol()
  // Without escaping both would be "a|b|<identity>|1|c|d".
  let left = run_identity("a|b", protocol, 1UL, identity_provenance("c", "d"))
  let right = run_identity("a", protocol, 1UL, identity_provenance("b|c", "d"))
  assert_true(left != right)
  assert_eq(left.split("|").count(), 5)
  assert_true(left.has_prefix("a%7Cb|"))
  assert_true(
    run_identity("50%", protocol, 1UL, identity_provenance("r", "t")).has_prefix(
      "50%25|",
    ),
  )
}
