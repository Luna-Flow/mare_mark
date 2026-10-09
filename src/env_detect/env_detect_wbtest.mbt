///|
test "iso8601_utc formats epoch milliseconds" {
  assert_eq(iso8601_utc(0UL), "1970-01-01T00:00:00Z")
  // Leap day, end of a day, and the millisecond part dropped.
  assert_eq(iso8601_utc(951782400000UL), "2000-02-29T00:00:00Z")
  assert_eq(iso8601_utc(951868799999UL), "2000-02-29T23:59:59Z")
  assert_eq(iso8601_utc(1791529902123UL), "2026-10-09T07:11:42Z")
  assert_eq(iso8601_utc(4107542400000UL), "2100-03-01T00:00:00Z")
  assert_eq(iso8601_utc(1704067199000UL), "2023-12-31T23:59:59Z")
}

///|
test "compact_utc keeps milliseconds" {
  assert_eq(compact_utc(0UL), "19700101T000000000Z")
  assert_eq(compact_utc(1791529902123UL), "20261009T071142123Z")
}

///|
test "compose_run_id uses entropy, else a sequence number" {
  assert_eq(
    compose_run_id(1791529902123UL, Some(b"\x00\x0f\xa0\xff"), 7),
    "20261009T071142123Z-000fa0ff",
  )
  assert_eq(compose_run_id(0UL, None, 7), "19700101T000000000Z-seq7")
  assert_eq(compose_run_id(0UL, Some(b""), 8), "19700101T000000000Z-seq8")
}

///|
test "settle records the fallback" {
  let undetected = []
  assert_eq(settle(undetected, "cpu", Some("x"), UNKNOWN), "x")
  assert_eq(settle(undetected, "os", None, UNKNOWN), UNKNOWN)
  assert_eq(undetected, ["os"])
}

///|
test "env_value skips blank variables and trims" {
  let blank = "MARE_MARK_ENV_DETECT_TEST_BLANK"
  let set = "MARE_MARK_ENV_DETECT_TEST_SET"
  let missing = "MARE_MARK_ENV_DETECT_TEST_MISSING"
  @env.set_env_var(blank, "  ")
  @env.set_env_var(set, " value \n")
  @env.unset_env_var(missing)
  assert_eq(env_value([missing, blank, set]), Some("value"))
  assert_eq(env_value([missing, blank]), None)
  assert_eq(or_env(Some("probe"), [set]), Some("probe"))
  assert_eq(or_env(None, [set]), Some("value"))
  @env.unset_env_var(blank)
  @env.unset_env_var(set)
}

///|
test "positive_int accepts only positive counts" {
  assert_eq(positive_int(" 12\n"), Some(12))
  assert_eq(positive_int("0"), None)
  assert_eq(positive_int("-3"), None)
  assert_eq(positive_int("many"), None)
}

///|
test "target_gc names the memory management of the target" {
  let gc = target_gc()
  assert_true(["rc", "wasm-gc", "js-engine"].contains(gc), msg=gc)
}

///|
test "describe_cpu appends the logical core count" {
  assert_eq(
    describe_cpu(Some("Apple M4"), Some(10)),
    Some("Apple M4 (10 logical cores)"),
  )
  assert_eq(describe_cpu(None, Some(10)), Some("unknown (10 logical cores)"))
  assert_eq(describe_cpu(Some("cpu"), Some(1)), Some("cpu (1 logical core)"))
  assert_eq(describe_cpu(Some("Apple M4"), None), Some("Apple M4"))
  assert_eq(describe_cpu(None, None), None)
}
