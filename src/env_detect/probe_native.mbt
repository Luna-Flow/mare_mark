///|
/// Upper bound on each probing subprocess.
const COMMAND_TIMEOUT_MS : Int = 5000

///|
fn target_runtime() -> String? {
  Some("native")
}

///|
/// Trimmed standard output of a command that exits 0 with non-blank output,
/// else `None` (also when the command is missing or times out).
async fn command_output(command : String, arguments : Array[String]) -> String? {
  let result = @async.with_timeout_opt(COMMAND_TIMEOUT_MS, () => {
    @process.collect_output(command, arguments)
  }) catch {
    _ => return None
  }
  match result {
    Some((0, stdout, _)) => non_blank(stdout.text())
    _ => None
  }
}

///|
/// `uname -sr`, for example `Linux 6.8.0-1017-azure` or `Darwin 24.1.0`.
async fn probe_os() -> String? {
  command_output("uname", ["-sr"])
}

///|
async fn probe_hostname() -> String? {
  command_output("uname", ["-n"])
}

///|
/// `model name` from `/proc/cpuinfo` on Linux, else
/// `sysctl -n machdep.cpu.brand_string` on macOS.
async fn probe_cpu() -> String? {
  let cpuinfo = @fs.read_file_to_string("/proc/cpuinfo") catch { _ => "" }
  if cpuinfo_model(cpuinfo) is Some(model) {
    return Some(model)
  }
  command_output("sysctl", ["-n", "machdep.cpu.brand_string"])
}

///|
async fn probe_logical_cores() -> Int? {
  command_output("getconf", ["_NPROCESSORS_ONLN"]).bind(positive_int)
}

///|
async fn probe_git_revision() -> String? {
  command_output("git", ["rev-parse", "HEAD"])
}

///|
/// The `model name` of the first processor in a Linux `/proc/cpuinfo`.
fn cpuinfo_model(cpuinfo : String) -> String? {
  for line in cpuinfo.split("\n") {
    let line = line.to_owned()
    if line.has_prefix("model name") {
      match line.find(":") {
        Some(index) => return non_blank(line[index + 1:].to_owned())
        None => ()
      }
    }
  }
  None
}
