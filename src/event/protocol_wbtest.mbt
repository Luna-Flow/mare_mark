///|
/// A protocol with every field set by label; the defaults differ from every
/// preset (`HierarchicalDatasetsAndRepeats`, `SharedBatchSize`, `MADTrim`,
/// `ConfirmatoryOnly` and the largest `UInt64` order seed).
fn sample_protocol(
  experiment_design? : @model.ExperimentDesign = HierarchicalDatasetsAndRepeats,
  warmup_iterations? : Int = 3,
  warmup_time_us? : Double? = Some(5000.0),
  target_batch_time_us? : Double = 50.0,
  max_sample_time_us? : Double = 200.0,
  batch_policy? : @model.BatchPolicy = SharedBatchSize,
  practical_delta_pct? : Double = 0.1,
  order_policy? : @model.OrderPolicy = BalancedBlocks(18446744073709551615UL),
  outlier_policy? : @model.OutlierPolicy = MADTrim,
  validation_coverage? : @model.ValidationCoverage = ConfirmatoryOnly,
  exploratory_samples? : Int = 100,
  repeats_per_dataset? : Int = 1,
) -> @model.RunProtocol {
  @model.RunProtocol::new(
    experiment_design,
    warmup_iterations,
    warmup_time_us,
    @model.CalibrationProtocol::new(
      target_batch_time_us, 7, 9, max_sample_time_us, batch_policy,
    ),
    practical_delta_pct,
    order_policy,
    outlier_policy,
    validation_coverage,
    exploratory_samples,
    5,
    repeats_per_dataset~,
  )
}

///|
/// Encodes, stringifies, parses and decodes `protocol`, and checks the result
/// equals the input in every field (the canonical encoding compares doubles
/// by bit pattern).
fn assert_protocol_round_trip(protocol : @model.RunProtocol) -> Unit raise {
  let text = protocol_json(protocol).stringify()
  let decoded = protocol_from_json(@json.parse(text)).unwrap()
  assert_eq(
    @model.protocol_canonical_encoding(decoded),
    @model.protocol_canonical_encoding(protocol),
  )
  assert_eq(
    @model.protocol_identity(decoded),
    @model.protocol_identity(protocol),
  )
}

///|
test "summary JSONL records the protocol, its identity and the seed" {
  let protocol = sample_protocol()
  let summary = @model.RunSummary::new(
    "run",
    1,
    0,
    1,
    true,
    None,
    protocol~,
    seed=42UL,
  )
  let sink = JsonlSink::new()
  ignore((sink.as_sink().finish)(summary))
  let value = @json.parse(sink.to_jsonl())
  guard value is Object(fields) else { fail("summary must be an object") }
  assert_true(fields.get("type") is Some(String("summary")))
  assert_true(fields.get("artifact_version") is Some(String("mmka_1")))
  assert_true(fields.get("seed") is Some(String("42")))
  guard fields.get("protocol_identity") is Some(String(identity)) else {
    fail("missing protocol_identity")
  }
  assert_eq(identity, @model.protocol_identity(protocol))
  guard fields.get("protocol") is Some(recorded) else {
    fail("missing protocol")
  }
  let decoded = protocol_from_json(recorded).unwrap()
  assert_eq(@model.protocol_identity(decoded), identity)
  guard recorded is Object(object) else { fail("protocol must be an object") }
  assert_true(object.get("outlier_policy") is Some(String("mad_trim")))
  assert_true(object.get("practical_delta_pct") is Some(Number(0.1, ..)))
  assert_true(
    object.get("order_policy")
    is Some(
      Object(
        {
          "kind": String("balanced_blocks"),
          "seed": String("18446744073709551615"),
          ..
        }
      )
    ),
  )
}

///|
test "summary JSONL omits protocol fields the summary does not carry" {
  let encoded = summary_json(@model.RunSummary::new("run", 0, 0, 0, true, None)).stringify()
  assert_true(!encoded.contains("\"protocol\""))
  assert_true(!encoded.contains("\"protocol_identity\""))
  assert_true(!encoded.contains("\"seed\""))
}

///|
test "protocol JSON round-trips every variant and edge value" {
  let variants = [
    sample_protocol(),
    sample_protocol(warmup_time_us=None),
    sample_protocol(order_policy=FixedOrder),
    sample_protocol(order_policy=BalancedBlocks(0UL)),
    sample_protocol(experiment_design=FixedDatasetRepeatedMeasurements),
    sample_protocol(experiment_design=MultipleDatasetsSingleMeasurement),
    sample_protocol(batch_policy=PerImplementation),
    sample_protocol(outlier_policy=ReportOnly),
    sample_protocol(outlier_policy=TukeyFence),
    sample_protocol(validation_coverage=EveryMeasurement),
    sample_protocol(validation_coverage=EveryDataset),
    sample_protocol(warmup_time_us=Some(-0.0), practical_delta_pct=1.0e-300),
    sample_protocol(
      warmup_iterations=-2147483648,
      exploratory_samples=2147483647,
    ),
    sample_protocol(
      warmup_time_us=Some(@double.not_a_number),
      practical_delta_pct=@double.infinity,
      max_sample_time_us=@double.neg_infinity,
    ),
  ]
  for protocol in variants {
    assert_protocol_round_trip(protocol)
  }
}

///|
test "protocol decoder reports the offending field" {
  let valid = protocol_json(sample_protocol())
  guard valid is Object(fields) else { fail("protocol must be an object") }
  fn with_field(key : String, value : Json) -> Json {
    let copy = Map::from_iter(fields.iter())
    copy[key] = value
    Json::object(copy)
  }

  fn without_field(key : String) -> Json {
    let copy = Map::from_iter(fields.iter())
    copy.remove(key)
    Json::object(copy)
  }

  fn error(json : Json) -> String {
    match protocol_from_json(json) {
      Err(message) => message
      Ok(_) => "ok"
    }
  }

  inspect(error(Json::array([])), content="protocol: expected an object")
  inspect(
    error(without_field("outlier_policy")),
    content="protocol.outlier_policy: missing",
  )
  inspect(
    error(with_field("warmup_iterations", Json::number(1.5))),
    content="protocol.warmup_iterations: expected an Int",
  )
  inspect(
    error(with_field("confirmatory_samples", Json::number(2147483648.0))),
    content="protocol.confirmatory_samples: expected an Int",
  )
  inspect(
    error(with_field("exploratory_samples", Json::string("1"))),
    content="protocol.exploratory_samples: expected an Int",
  )
  inspect(
    error(with_field("practical_delta_pct", Json::boolean(true))),
    content="protocol.practical_delta_pct: expected a number",
  )
  inspect(
    error(with_field("warmup_time_us", Json::string("5"))),
    content="protocol.warmup_time_us: expected a number",
  )
  inspect(
    error(with_field("outlier_policy", Json::number(1.0))),
    content="protocol.outlier_policy: expected a string",
  )
  inspect(
    error(with_field("validation_coverage", Json::string("sometimes"))),
    content="protocol.validation_coverage: unknown value 'sometimes'",
  )
  inspect(
    error(with_field("calibration", Json::null())),
    content="protocol.calibration: expected an object",
  )
  inspect(
    error(
      with_field(
        "calibration",
        Json::object({ "target_batch_time_us": Json::number(1.0) }),
      ),
    ),
    content="protocol.calibration.min_batch_iterations: missing",
  )
  inspect(
    error(with_field("order_policy", Json::string("fixed_order"))),
    content="protocol.order_policy: expected an object",
  )
  inspect(
    error(
      with_field(
        "order_policy",
        Json::object({ "kind": Json::string("random") }),
      ),
    ),
    content="protocol.order_policy.kind: expected 'fixed_order' or 'balanced_blocks'",
  )
  inspect(
    error(
      with_field(
        "order_policy",
        Json::object({ "kind": Json::string("balanced_blocks") }),
      ),
    ),
    content="protocol.order_policy.seed: missing",
  )
  for
    seed in [
      Json::number(1.0),
      Json::string("abc"),
      Json::string("+1"),
      Json::string("01"),
      Json::string("18446744073709551616"),
    ] {
    let message = error(
      with_field(
        "order_policy",
        Json::object({ "kind": Json::string("balanced_blocks"), "seed": seed }),
      ),
    )
    assert_true(
      message.has_prefix("protocol.order_policy.seed: expected a decimal"),
    )
  }
  // Unknown keys are ignored, so later additive fields stay readable.
  assert_true(protocol_from_json(with_field("future", Json::null())) is Ok(_))
}

///|
test "protocol JSON records repeats per dataset" {
  let protocol = sample_protocol(exploratory_samples=10, repeats_per_dataset=5)
  let encoded = protocol_json(protocol).stringify()
  assert_true(encoded.contains("\"repeats_per_dataset\":5"))
  assert_protocol_round_trip(protocol)
}

///|
test "protocol decoder defaults a missing repeats_per_dataset to 1" {
  guard protocol_json(sample_protocol(repeats_per_dataset=5)) is Object(fields) else {
    fail("protocol must be an object")
  }
  let legacy = Map::from_iter(fields.iter())
  legacy.remove("repeats_per_dataset")
  let decoded = protocol_from_json(Json::object(legacy)).unwrap()
  assert_eq(decoded.repeats_per_dataset, 1)
  assert_eq(
    @model.protocol_identity(decoded),
    @model.protocol_identity(sample_protocol()),
  )
  let invalid = Map::from_iter(fields.iter())
  invalid["repeats_per_dataset"] = Json::string("5")
  assert_true(
    protocol_from_json(Json::object(invalid))
    is Err("protocol.repeats_per_dataset: expected an Int"),
  )
  invalid["repeats_per_dataset"] = Json::number(2.5)
  assert_true(
    protocol_from_json(Json::object(invalid))
    is Err("protocol.repeats_per_dataset: expected an Int"),
  )
}
