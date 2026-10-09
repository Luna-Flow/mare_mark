///|
/// Value of a text field that could not be detected and was not overridden.
pub const UNKNOWN : String = "unknown"

///|
/// `concurrency` value when it is not overridden. `concurrency` is the
/// benchmark's own degree of parallelism, which the process cannot detect.
pub const UNKNOWN_CONCURRENCY : Int = 0

///|
/// `clock` value when it is not overridden. The runner times with the
/// monotonic clock of `moonbitlang/core/bench` on every target.
pub const DEFAULT_CLOCK : String = "monotonic"

///|
/// `device` value when it is not overridden (same as
/// `PerformanceEnvironment::new`).
pub const DEFAULT_DEVICE : String = "host"

///|
/// `frequency_policy` value when it is not overridden (same as
/// `PerformanceEnvironment::new`).
pub const DEFAULT_FREQUENCY_POLICY : String = "uncontrolled"

///|
/// Environment variables read, in order, for the source revision.
let revision_variables : Array[String] = [
  "GITHUB_SHA", "CI_COMMIT_SHA", "GIT_COMMIT",
]

///|
/// Environment variable read for the toolchain description.
let toolchain_variable : String = "MARE_MARK_TOOLCHAIN"

///|
/// A detected `EnvironmentSnapshot` and the fields that were neither detected
/// nor overridden.
///
/// `undetected` holds field names as they appear in the JSONL record
/// (`"toolchain"`, `"cpu"`, `"concurrency"`, ...), in snapshot order. Such a
/// field holds `UNKNOWN`, `UNKNOWN_CONCURRENCY` or one of the documented
/// `DEFAULT_*` constants.
pub struct DetectedEnvironment {
  snapshot : @model.EnvironmentSnapshot
  undetected : Array[String]
}

///|
/// Detects the environment of the running process.
///
/// Every field can be overridden by its labelled argument; an overridden
/// field is not probed and is never reported as undetected. Detection never
/// fails: a field that cannot be detected gets `UNKNOWN` (or the documented
/// constant) and its name is added to `undetected`.
///
/// - `target`, `gc`: fixed per compilation target.
/// - `runtime`: `"native"` on native and LLVM, `"node <version>"` on Node.js.
/// - `toolchain`: the `MARE_MARK_TOOLCHAIN` environment variable.
/// - `compiler_flags`, `dtype_abi`: never detected.
/// - `os`, `hostname`: from the host on native and Node.js, else from `OS`,
///   `HOSTNAME` / `COMPUTERNAME`.
/// - `cpu`: the CPU model (host probe, else `PROCESSOR_IDENTIFIER`) followed
///   by the logical core count (host probe, else `NUMBER_OF_PROCESSORS`), for
///   example `"Apple M4 (10 logical cores)"`. With only the core count it is
///   `"unknown (10 logical cores)"`, with only the model just the model; it is
///   reported as undetected only when neither is known.
/// - `concurrency`: the benchmark's own degree of parallelism, never
///   detected (the core count goes into `cpu`); `UNKNOWN_CONCURRENCY` unless
///   overridden.
/// - `clock`, `device`, `frequency_policy`: never detected; they default to
///   `DEFAULT_CLOCK`, `DEFAULT_DEVICE` and `DEFAULT_FREQUENCY_POLICY`.
/// - `timestamp`: the current UTC time as `YYYY-MM-DDTHH:MM:SSZ`.
/// - `revision`: `GITHUB_SHA`, `CI_COMMIT_SHA` or `GIT_COMMIT`, else
///   `git rev-parse HEAD` on native.
/// - `run_id`: generated, see `new_run_id`.
///
/// It is asynchronous because native detection runs subprocesses (`uname`,
/// `getconf`, `sysctl`, `git`); on other targets it does not suspend.
#warnings("-unused_async")
pub async fn detect(
  target? : @model.ExecutionTarget,
  toolchain? : String,
  compiler_flags? : String,
  dtype_abi? : String,
  runtime? : String,
  cpu? : String,
  gc? : String,
  concurrency? : Int,
  clock? : String,
  device? : String,
  frequency_policy? : String,
  os? : String,
  hostname? : String,
  timestamp? : String,
  revision? : String,
  run_id? : String,
) -> DetectedEnvironment {
  let undetected = []
  let target = target.unwrap_or(current_target())
  let toolchain = match toolchain {
    Some(value) => value
    None =>
      settle(undetected, "toolchain", env_value([toolchain_variable]), UNKNOWN)
  }
  let compiler_flags = match compiler_flags {
    Some(value) => value
    None => settle(undetected, "compiler_flags", None, UNKNOWN)
  }
  let dtype_abi = match dtype_abi {
    Some(value) => value
    None => settle(undetected, "dtype_abi", None, UNKNOWN)
  }
  let runtime = match runtime {
    Some(value) => value
    None => settle(undetected, "runtime", target_runtime(), UNKNOWN)
  }
  let cpu = match cpu {
    Some(value) => value
    None => {
      let model = or_env(probe_cpu(), ["PROCESSOR_IDENTIFIER"])
      let cores = match probe_logical_cores() {
        Some(count) => Some(count)
        None => env_value(["NUMBER_OF_PROCESSORS"]).bind(positive_int)
      }
      settle(undetected, "cpu", describe_cpu(model, cores), UNKNOWN)
    }
  }
  let gc = gc.unwrap_or(target_gc())
  let concurrency = match concurrency {
    Some(value) => value
    None => {
      undetected.push("concurrency")
      UNKNOWN_CONCURRENCY
    }
  }
  let clock = match clock {
    Some(value) => value
    None => settle(undetected, "clock", None, DEFAULT_CLOCK)
  }
  let device = match device {
    Some(value) => value
    None => settle(undetected, "device", None, DEFAULT_DEVICE)
  }
  let frequency_policy = match frequency_policy {
    Some(value) => value
    None =>
      settle(undetected, "frequency_policy", None, DEFAULT_FREQUENCY_POLICY)
  }
  let os = match os {
    Some(value) => value
    None => settle(undetected, "os", or_env(probe_os(), ["OS"]), UNKNOWN)
  }
  let hostname = match hostname {
    Some(value) => value
    None =>
      settle(
        undetected,
        "hostname",
        or_env(probe_hostname(), ["HOSTNAME", "COMPUTERNAME"]),
        UNKNOWN,
      )
  }
  let now = @env.now()
  let timestamp = timestamp.unwrap_or(iso8601_utc(now))
  let revision = match revision {
    Some(value) => value
    None => {
      let detected = match env_value(revision_variables) {
        Some(value) => Some(value)
        None => probe_git_revision()
      }
      settle(undetected, "revision", detected, UNKNOWN)
    }
  }
  let run_id = run_id.unwrap_or(new_run_id(now))
  {
    snapshot: @model.EnvironmentSnapshot::new(
      @model.SemanticEnvironment::new(
        target, toolchain, compiler_flags, dtype_abi,
      ),
      @model.PerformanceEnvironment::new(
        runtime,
        cpu,
        gc,
        concurrency,
        clock,
        device~,
        frequency_policy~,
      ),
      @model.ProvenanceEnvironment::new(
        os, hostname, timestamp, revision, run_id,
      ),
    ),
    undetected,
  }
}

///|
/// Generates a run id for a run started at `now_ms` (milliseconds since the
/// Unix epoch).
///
/// The format is `YYYYMMDDTHHMMSSmmmZ-<16 lowercase hex digits>`, the hex
/// digits being 8 bytes from the platform entropy source. When the platform
/// has no entropy source the suffix is `seq<n>`, a per-process counter, and
/// the id is unique only within the process.
pub fn new_run_id(now_ms : UInt64) -> String {
  run_sequence.val += 1
  compose_run_id(now_ms, @env.rand(8), run_sequence.val)
}

///|
let run_sequence : Ref[Int] = Ref(0)

///|
fn compose_run_id(now_ms : UInt64, entropy : Bytes?, sequence : Int) -> String {
  let suffix = match entropy {
    Some(bytes) if bytes.length() > 0 => hex(bytes)
    _ => "seq" + sequence.to_string()
  }
  compact_utc(now_ms) + "-" + suffix
}

///|
fn settle(
  undetected : Array[String],
  field : String,
  detected : String?,
  fallback : String,
) -> String {
  match detected {
    Some(value) => value
    None => {
      undetected.push(field)
      fallback
    }
  }
}

///|
/// The first of `names` that is set to a non-blank value, trimmed.
fn env_value(names : Array[String]) -> String? {
  for name in names {
    if @env.get_env_var(name).bind(non_blank) is Some(value) {
      return Some(value)
    }
  }
  None
}

///|
fn non_blank(text : String) -> String? {
  let trimmed = text.trim().to_owned()
  if trimmed == "" {
    None
  } else {
    Some(trimmed)
  }
}

///|
fn positive_int(text : String) -> Int? {
  let value = @string.parse_int(text.trim()) catch { _ => return None }
  if value > 0 {
    Some(value)
  } else {
    None
  }
}

///|
fn hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let builder = StringBuilder()
  for byte in bytes {
    let value = byte.to_int()
    builder.write_char(digits[value / 16].unsafe_to_char())
    builder.write_char(digits[value % 16].unsafe_to_char())
  }
  builder.to_string()
}

///|
fn pad(value : Int, width : Int) -> String {
  value.to_string().pad_start(width, '0')
}

///|
/// Splits milliseconds since the Unix epoch into
/// `(year, month, day, hour, minute, second, millisecond)` in UTC, using the
/// proleptic Gregorian calendar.
fn utc_fields(now_ms : UInt64) -> (Int, Int, Int, Int, Int, Int, Int) {
  let ms = now_ms.reinterpret_as_int64()
  let millisecond = (ms % 1000L).to_int()
  let seconds = ms / 1000L
  let days = seconds / 86400L
  let second_of_day = (seconds % 86400L).to_int()
  // Days to civil date, after Howard Hinnant's `civil_from_days`.
  let z = days + 719468L
  let era = z / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let day = (doy - (153L * mp + 2L) / 5L + 1L).to_int()
  let month = (if mp < 10L { mp + 3L } else { mp - 9L }).to_int()
  let year = (yoe + era * 400L).to_int() + (if month <= 2 { 1 } else { 0 })
  (
    year,
    month,
    day,
    second_of_day / 3600,
    second_of_day % 3600 / 60,
    second_of_day % 60,
    millisecond,
  )
}

///|
/// ISO 8601 UTC timestamp with second precision: `YYYY-MM-DDTHH:MM:SSZ`.
fn iso8601_utc(now_ms : UInt64) -> String {
  let (year, month, day, hour, minute, second, _) = utc_fields(now_ms)
  pad(year, 4) +
  "-" +
  pad(month, 2) +
  "-" +
  pad(day, 2) +
  "T" +
  pad(hour, 2) +
  ":" +
  pad(minute, 2) +
  ":" +
  pad(second, 2) +
  "Z"
}

///|
/// Basic-format UTC timestamp with millisecond precision:
/// `YYYYMMDDTHHMMSSmmmZ`.
fn compact_utc(now_ms : UInt64) -> String {
  let (year, month, day, hour, minute, second, millisecond) = utc_fields(now_ms)
  pad(year, 4) +
  pad(month, 2) +
  pad(day, 2) +
  "T" +
  pad(hour, 2) +
  pad(minute, 2) +
  pad(second, 2) +
  pad(millisecond, 3) +
  "Z"
}

///|
/// `detected`, else the first of the environment variables `names` that is set.
fn or_env(detected : String?, names : Array[String]) -> String? {
  match detected {
    Some(value) => Some(value)
    None => env_value(names)
  }
}

///|
/// CPU text from the model and the logical core count; `None` when neither
/// is known.
fn describe_cpu(model : String?, cores : Int?) -> String? {
  match (model, cores) {
    (None, None) => None
    (Some(model), None) => Some(model)
    (model, Some(count)) => {
      let unit = if count == 1 { "logical core" } else { "logical cores" }
      Some(
        model.unwrap_or(UNKNOWN) + " (" + count.to_string() + " " + unit + ")",
      )
    }
  }
}
