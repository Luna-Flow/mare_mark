///|
#cfg(target="native")
let expected_target : String = "native"

///|
#cfg(target="js")
let expected_target : String = "js"

///|
#cfg(target="wasm")
let expected_target : String = "wasm"

///|
#cfg(target="wasm-gc")
let expected_target : String = "wasm-gc"

///|
#cfg(target="llvm")
let expected_target : String = "llvm"

///|
let field_names : Array[String] = [
  "target", "toolchain", "compiler_flags", "dtype_abi", "runtime", "cpu", "gc", "concurrency",
  "clock", "device", "frequency_policy", "os", "hostname", "timestamp", "revision",
  "run_id",
]

///|
fn is_digit(char : Char) -> Bool {
  char >= '0' && char <= '9'
}

///|
/// Checks `text` against a shape where `9` stands for any decimal digit.
fn has_shape(text : String, shape : String) -> Bool {
  let text = text.to_array()
  let shape = shape.to_array()
  if text.length() != shape.length() {
    return false
  }
  for index in 0..<text.length() {
    let ok = if shape[index] == '9' {
      is_digit(text[index])
    } else {
      text[index] == shape[index]
    }
    if !ok {
      return false
    }
  }
  true
}

///|
async test "detect reports the target under test" {
  let detected = @env_detect.detect()
  assert_eq(detected.snapshot.semantic.target.text(), expected_target)
  assert_true(detected.snapshot.performance.gc != @env_detect.UNKNOWN)
  assert_false(detected.undetected.contains("target"))
  assert_false(detected.undetected.contains("gc"))
}

///|
async test "detect stamps a well-formed UTC timestamp" {
  let detected = @env_detect.detect()
  let timestamp = detected.snapshot.provenance.timestamp
  assert_true(has_shape(timestamp, "9999-99-99T99:99:99Z"), msg=timestamp)
  assert_true(timestamp >= "2024-01-01T00:00:00Z", msg=timestamp)
  assert_false(detected.undetected.contains("timestamp"))
}

///|
async test "detect generates a distinct run id per call" {
  let first = @env_detect.detect().snapshot.provenance.run_id
  let second = @env_detect.detect().snapshot.provenance.run_id
  assert_true(first != second, msg=first)
  for run_id in [first, second] {
    assert_true(
      has_shape(run_id[:19].to_owned(), "99999999T999999999Z"),
      msg=run_id,
    )
    assert_eq(run_id[19:20].to_owned(), "-")
  }
}

///|
async test "detect reports undetected fields with their fallbacks" {
  let detected = @env_detect.detect()
  let snapshot = detected.snapshot
  // Never detectable: always reported unless overridden.
  for
    field in [
      "compiler_flags", "dtype_abi", "clock", "device", "frequency_policy",
    ] {
    assert_true(detected.undetected.contains(field), msg=field)
  }
  assert_eq(snapshot.semantic.compiler_flags, @env_detect.UNKNOWN)
  assert_eq(snapshot.semantic.dtype_abi, @env_detect.UNKNOWN)
  assert_eq(snapshot.performance.clock, @env_detect.DEFAULT_CLOCK)
  assert_eq(snapshot.performance.device, @env_detect.DEFAULT_DEVICE)
  assert_eq(
    snapshot.performance.frequency_policy,
    @env_detect.DEFAULT_FREQUENCY_POLICY,
  )
  // Every reported name is a snapshot field, reported once.
  for field in detected.undetected {
    assert_true(field_names.contains(field), msg=field)
    assert_eq(detected.undetected.filter(name => name == field).length(), 1)
  }
  // A field is reported exactly when it holds its fallback.
  let text_fields = [
    ("toolchain", snapshot.semantic.toolchain),
    ("runtime", snapshot.performance.runtime),
    ("cpu", snapshot.performance.cpu),
    ("os", snapshot.provenance.os),
    ("hostname", snapshot.provenance.hostname),
    ("revision", snapshot.provenance.revision),
  ]
  for pair in text_fields {
    let (field, value) = pair
    assert_eq(
      detected.undetected.contains(field),
      value == @env_detect.UNKNOWN,
      msg=field + "=" + value,
    )
  }
  assert_eq(
    detected.undetected.contains("concurrency"),
    snapshot.performance.concurrency == @env_detect.UNKNOWN_CONCURRENCY,
  )
  assert_true(snapshot.performance.concurrency >= 0)
}

///|
async test "overrides win and are not reported" {
  let detected = @env_detect.detect(
    target=Custom("custom-target"),
    toolchain="moonc 0.10",
    compiler_flags="release",
    dtype_abi="i32",
    runtime="my-runtime",
    cpu="my-cpu",
    gc="my-gc",
    concurrency=3,
    clock="my-clock",
    device="my-device",
    frequency_policy="pinned",
    os="my-os",
    hostname="my-host",
    timestamp="2026-10-08T12:00:00Z",
    revision="abc123",
    run_id="my-run",
  )
  let snapshot = detected.snapshot
  assert_eq(detected.undetected, [])
  assert_eq(snapshot.semantic.target.text(), "custom-target")
  assert_eq(snapshot.semantic.toolchain, "moonc 0.10")
  assert_eq(snapshot.semantic.compiler_flags, "release")
  assert_eq(snapshot.semantic.dtype_abi, "i32")
  assert_eq(snapshot.performance.runtime, "my-runtime")
  assert_eq(snapshot.performance.cpu, "my-cpu")
  assert_eq(snapshot.performance.gc, "my-gc")
  assert_eq(snapshot.performance.concurrency, 3)
  assert_eq(snapshot.performance.clock, "my-clock")
  assert_eq(snapshot.performance.device, "my-device")
  assert_eq(snapshot.performance.frequency_policy, "pinned")
  assert_eq(snapshot.provenance.os, "my-os")
  assert_eq(snapshot.provenance.hostname, "my-host")
  assert_eq(snapshot.provenance.timestamp, "2026-10-08T12:00:00Z")
  assert_eq(snapshot.provenance.revision, "abc123")
  assert_eq(snapshot.provenance.run_id, "my-run")
}

///|
async test "a partial override keeps the other fields detected" {
  let detected = @env_detect.detect(compiler_flags="release", clock="tsc")
  assert_eq(detected.snapshot.semantic.compiler_flags, "release")
  assert_eq(detected.snapshot.performance.clock, "tsc")
  assert_false(detected.undetected.contains("compiler_flags"))
  assert_false(detected.undetected.contains("clock"))
  assert_true(detected.undetected.contains("dtype_abi"))
  assert_eq(detected.snapshot.semantic.target.text(), expected_target)
}

///|
test "new_run_id has the documented shape" {
  let run_id = @env_detect.new_run_id(0UL)
  assert_true(run_id.has_prefix("19700101T000000000Z-"), msg=run_id)
  assert_true(run_id != @env_detect.new_run_id(0UL))
}
