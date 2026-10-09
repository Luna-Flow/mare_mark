///|
/// JSON number for a `Double`. Non-finite values, which JSON numbers cannot
/// hold, are the strings `"NaN"`, `"Infinity"` and `"-Infinity"`, as in
/// `moonbitlang/core/json`. `-0.0` is written as `-0`, since the default
/// number text drops the sign of zero.
fn double_json(value : Double) -> Json {
  if value == 0.0 && value.reinterpret_as_uint64() != 0UL {
    Json::number(value, repr="-0")
  } else if value.is_nan() {
    Json::string("NaN")
  } else if value.is_pos_inf() {
    Json::string("Infinity")
  } else if value.is_neg_inf() {
    Json::string("-Infinity")
  } else {
    Json::number(value)
  }
}

///|
fn order_policy_json(policy : @model.OrderPolicy) -> Json {
  match policy {
    FixedOrder => Json::object({ "kind": Json::string("fixed_order") })
    BalancedBlocks(seed) =>
      Json::object({
        "kind": Json::string("balanced_blocks"),
        "seed": Json::string(seed.to_string()),
      })
  }
}

///|
/// JSON object holding every field of a `RunProtocol`, as written to the
/// `protocol` field of a JSONL `summary` event.
///
/// Keys are the `RunProtocol` and `CalibrationProtocol` field names. Enums are
/// their `text()` tags, `warmup_time_us` is `null` when absent, and
/// `order_policy` is `{"kind":"fixed_order"}` or
/// `{"kind":"balanced_blocks","seed":"<decimal UInt64>"}` (a string, since a
/// JSON number cannot hold every `UInt64`). `protocol_from_json` reverses it.
pub fn protocol_json(protocol : @model.RunProtocol) -> Json {
  let calibration = protocol.calibration
  Json::object({
    "experiment_design": Json::string(protocol.experiment_design.text()),
    "warmup_iterations": Json::number(protocol.warmup_iterations.to_double()),
    "warmup_time_us": match protocol.warmup_time_us {
      Some(value) => double_json(value)
      None => Json::null()
    },
    "calibration": Json::object({
      "target_batch_time_us": double_json(calibration.target_batch_time_us),
      "min_batch_iterations": Json::number(
        calibration.min_batch_iterations.to_double(),
      ),
      "max_batch_iterations": Json::number(
        calibration.max_batch_iterations.to_double(),
      ),
      "max_sample_time_us": double_json(calibration.max_sample_time_us),
      "batch_policy": Json::string(calibration.batch_policy.text()),
    }),
    "practical_delta_pct": double_json(protocol.practical_delta_pct),
    "order_policy": order_policy_json(protocol.order_policy),
    "outlier_policy": Json::string(protocol.outlier_policy.text()),
    "validation_coverage": Json::string(protocol.validation_coverage.text()),
    "exploratory_samples": Json::number(
      protocol.exploratory_samples.to_double(),
    ),
    "confirmatory_samples": Json::number(
      protocol.confirmatory_samples.to_double(),
    ),
    "repeats_per_dataset": Json::number(
      protocol.repeats_per_dataset.to_double(),
    ),
  })
}

///|
priv suberror ProtocolDecodeError {
  ProtocolDecodeError(String)
}

///|
fn decode_object(
  json : Json,
  path : String,
) -> Map[String, Json] raise ProtocolDecodeError {
  guard json is Object(fields) else {
    raise ProtocolDecodeError(path + ": expected an object")
  }
  fields
}

///|
fn decode_field(
  fields : Map[String, Json],
  path : String,
  key : String,
) -> Json raise ProtocolDecodeError {
  guard fields.get(key) is Some(value) else {
    raise ProtocolDecodeError(path + "." + key + ": missing")
  }
  value
}

///|
fn decode_int(
  fields : Map[String, Json],
  path : String,
  key : String,
) -> Int raise ProtocolDecodeError {
  guard decode_field(fields, path, key) is Number(value, ..) &&
    value >= -2147483648.0 &&
    value <= 2147483647.0 &&
    value.floor() == value else {
    raise ProtocolDecodeError(path + "." + key + ": expected an Int")
  }
  value.to_int()
}

///|
fn decode_double_value(
  json : Json,
  path : String,
) -> Double raise ProtocolDecodeError {
  match json {
    Number(value, ..) => value
    String("NaN") => @double.not_a_number
    String("Infinity") => @double.infinity
    String("-Infinity") => @double.neg_infinity
    _ => raise ProtocolDecodeError(path + ": expected a number")
  }
}

///|
fn decode_double(
  fields : Map[String, Json],
  path : String,
  key : String,
) -> Double raise ProtocolDecodeError {
  decode_double_value(decode_field(fields, path, key), path + "." + key)
}

///|
/// Decodes a field holding the `text()` tag of one of `variants`.
fn[T] decode_tag(
  fields : Map[String, Json],
  path : String,
  key : String,
  variants : Array[T],
  text : (T) -> String,
) -> T raise ProtocolDecodeError {
  guard decode_field(fields, path, key) is String(tag) else {
    raise ProtocolDecodeError(path + "." + key + ": expected a string")
  }
  for variant in variants {
    if text(variant) == tag {
      return variant
    }
  }
  raise ProtocolDecodeError(path + "." + key + ": unknown value '" + tag + "'")
}

///|
fn decode_uint64_text(
  json : Json,
  path : String,
) -> UInt64 raise ProtocolDecodeError {
  guard json is String(text) else {
    raise ProtocolDecodeError(path + ": expected a decimal string")
  }
  let value = @string.parse_uint64(text, base=10) catch {
    _ => raise ProtocolDecodeError(path + ": expected a decimal UInt64")
  }
  // Only the canonical decimal form is accepted (no sign, no leading zeros,
  // no `_` separators), so the text round-trips.
  guard value.to_string() == text else {
    raise ProtocolDecodeError(path + ": expected a decimal UInt64")
  }
  value
}

///|
fn decode_order_policy(
  json : Json,
  path : String,
) -> @model.OrderPolicy raise ProtocolDecodeError {
  let fields = decode_object(json, path)
  match decode_field(fields, path, "kind") {
    String("fixed_order") => FixedOrder
    String("balanced_blocks") =>
      BalancedBlocks(
        decode_uint64_text(decode_field(fields, path, "seed"), path + ".seed"),
      )
    _ =>
      raise ProtocolDecodeError(
        path + ".kind: expected 'fixed_order' or 'balanced_blocks'",
      )
  }
}

///|
fn decode_protocol(json : Json) -> @model.RunProtocol raise ProtocolDecodeError {
  let path = "protocol"
  let fields = decode_object(json, path)
  let calibration_path = path + ".calibration"
  let calibration_fields = decode_object(
    decode_field(fields, path, "calibration"),
    calibration_path,
  )
  let calibration = @model.CalibrationProtocol::new(
    decode_double(calibration_fields, calibration_path, "target_batch_time_us"),
    decode_int(calibration_fields, calibration_path, "min_batch_iterations"),
    decode_int(calibration_fields, calibration_path, "max_batch_iterations"),
    decode_double(calibration_fields, calibration_path, "max_sample_time_us"),
    decode_tag(
      calibration_fields,
      calibration_path,
      "batch_policy",
      [PerImplementation, SharedBatchSize],
      @model.BatchPolicy::text,
    ),
  )
  let warmup_time_us = match decode_field(fields, path, "warmup_time_us") {
    Null => None
    value => Some(decode_double_value(value, path + ".warmup_time_us"))
  }
  @model.RunProtocol::new(
    decode_tag(
      fields,
      path,
      "experiment_design",
      [
        FixedDatasetRepeatedMeasurements,
        MultipleDatasetsSingleMeasurement,
        HierarchicalDatasetsAndRepeats,
      ],
      @model.ExperimentDesign::text,
    ),
    decode_int(fields, path, "warmup_iterations"),
    warmup_time_us,
    calibration,
    decode_double(fields, path, "practical_delta_pct"),
    decode_order_policy(
      decode_field(fields, path, "order_policy"),
      path + ".order_policy",
    ),
    decode_tag(
      fields,
      path,
      "outlier_policy",
      [ReportOnly, TukeyFence, MADTrim],
      @model.OutlierPolicy::text,
    ),
    decode_tag(
      fields,
      path,
      "validation_coverage",
      [EveryMeasurement, EveryDataset, ConfirmatoryOnly],
      @model.ValidationCoverage::text,
    ),
    decode_int(fields, path, "exploratory_samples"),
    decode_int(fields, path, "confirmatory_samples"),
    // Records written before `repeats_per_dataset` existed omit it; their
    // runs used the default of 1.
    repeats_per_dataset=if fields.contains("repeats_per_dataset") {
      decode_int(fields, path, "repeats_per_dataset")
    } else {
      1
    },
  )
}

///|
/// Decodes the `protocol` object of a JSONL `summary` event, as written by
/// `protocol_json`, back into the `RunProtocol` the run used.
///
/// Every field is required except `repeats_per_dataset`, which defaults to `1`
/// for records written before it existed; unknown keys are ignored. The
/// decoding is exact, so for a record written by this version
/// `@model.protocol_identity` of the decoded protocol equals the
/// `protocol_identity` recorded next to it. Identities recorded before
/// `repeats_per_dataset` joined the canonical encoding differ, because the
/// encoding they were computed from did not contain it. Errors name the
/// offending field, e.g. `protocol.calibration.batch_policy: unknown value 'x'`.
pub fn protocol_from_json(json : Json) -> Result[@model.RunProtocol, String] {
  try decode_protocol(json) catch {
    ProtocolDecodeError(message) => Err(message)
  } noraise {
    protocol => Ok(protocol)
  }
}
