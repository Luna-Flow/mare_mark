///|
test "version ADTs own identifiers and lifecycle" {
  assert_eq(ProtocolVersion::V1.identifier(), "mmkp_1")
  assert_eq(ArtifactVersion::V1.identifier(), "mmka_1")
  assert_eq(SchemaVersion::V1.identifier(), "mmks_1")
  assert_true(ProtocolVersion::V1.lifecycle() is Supported)
  assert_true(ArtifactVersion::V1.lifecycle() is Supported)
  assert_true(SchemaVersion::V1.lifecycle() is Supported)
}

///|
test "execution outcomes preserve value, flags, and failure kinds" {
  let value = ExecutionOutcome::value(7)
  assert_eq(value.kind(), "value")
  assert_true(value.value_option() is Some(7))
  assert_true(value.flags().is_empty())
  let raised = ExecutionOutcome::raised_flags(7, ["inexact"])
  assert_eq(raised.kind(), "raised_flags")
  assert_true(raised.flags() == ["inexact"])
  assert_true(raised.value_option() is Some(7))
  assert_eq(
    (ExecutionOutcome::Trapped("overflow", ["overflow"]) : ExecutionOutcome[Int]).kind(),
    "trapped",
  )
  assert_eq(
    (ExecutionOutcome::Timeout(10, "slow") : ExecutionOutcome[Int]).kind(),
    "timeout",
  )
  assert_eq(
    (ExecutionOutcome::Aborted(2, "stderr") : ExecutionOutcome[Int]).kind(),
    "aborted",
  )
}

///|
test "artifact and protocol identities include semantic boundaries" {
  let first = RunProtocol::new(
    ExperimentDesign::FixedDatasetRepeatedMeasurements,
    1,
    None,
    CalibrationProtocol::new(10.0, 1, 10, 100.0, BatchPolicy::PerImplementation),
    5.0,
    OrderPolicy::FixedOrder,
    OutlierPolicy::ReportOnly,
    ValidationCoverage::ConfirmatoryOnly,
    1,
    2,
  )
  let second = RunProtocol::new(
    ExperimentDesign::FixedDatasetRepeatedMeasurements,
    2,
    None,
    first.calibration,
    5.0,
    OrderPolicy::FixedOrder,
    OutlierPolicy::ReportOnly,
    ValidationCoverage::ConfirmatoryOnly,
    1,
    2,
  )
  assert_true(protocol_identity(first) != protocol_identity(second))
  assert_true(
    artifact_identity("case", "impl", 0, first) !=
    artifact_identity("case", "impl", 0, second),
  )
}

///|
test "environment compatibility excludes provenance but checks performance" {
  let semantic = SemanticEnvironment::new(
    ExecutionTarget::Native,
    "moon",
    "-O2",
    "f64",
  )
  let performance = PerformanceEnvironment::new(
    "runtime", "cpu", "gc", 2, "monotonic",
  )
  let first = EnvironmentSnapshot::new(
    semantic,
    performance,
    ProvenanceEnvironment::new("os", "host-a", "now", "rev-a", "run-a"),
  )
  let same_run = EnvironmentSnapshot::new(
    semantic,
    performance,
    ProvenanceEnvironment::new("os", "host-b", "later", "rev-b", "run-b"),
  )
  let different_cpu = EnvironmentSnapshot::new(
    semantic,
    PerformanceEnvironment::new("runtime", "cpu-b", "gc", 2, "monotonic"),
    ProvenanceEnvironment::new("os", "host-a", "now", "rev-a", "run-a"),
  )
  assert_true(environment_compatible(first, same_run))
  assert_true(!environment_compatible(first, different_cpu))
}
