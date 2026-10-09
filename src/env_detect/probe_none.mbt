///|
/// The wasm, wasm-gc and LLVM builds have no host probe; detection falls back
/// to environment variables.
fn target_runtime() -> String? {
  match current_target() {
    Llvm => Some("native")
    _ => None
  }
}

///|
fn probe_os() -> String? {
  None
}

///|
fn probe_hostname() -> String? {
  None
}

///|
fn probe_cpu() -> String? {
  None
}

///|
fn probe_logical_cores() -> Int? {
  None
}

///|
fn probe_git_revision() -> String? {
  None
}
