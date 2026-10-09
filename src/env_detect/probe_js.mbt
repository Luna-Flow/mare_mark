///|
/// `"node <version>"` when running on Node.js.
fn target_runtime() -> String? {
  js_node_version()
}

///|
extern "js" fn js_node_version() -> String? =
  #| function() {
  #|   if (typeof process !== "undefined" && process.versions && typeof process.versions.node === "string") {
  #|     return "node " + process.versions.node;
  #|   }
  #|   return null;
  #| }

///|
/// Queries Node's `os` module (through `process.getBuiltinModule`) for one
/// fact: 0 the OS type and release, 1 the hostname, 2 the first CPU model.
extern "js" fn js_os_fact(fact : Int) -> String? =
  #| function(fact) {
  #|   try {
  #|     if (typeof process === "undefined" || typeof process.getBuiltinModule !== "function") {
  #|       return null;
  #|     }
  #|     const os = process.getBuiltinModule("os");
  #|     if (!os) {
  #|       return null;
  #|     }
  #|     if (fact === 0) {
  #|       return os.type() + " " + os.release();
  #|     }
  #|     if (fact === 1) {
  #|       return os.hostname();
  #|     }
  #|     const cpus = os.cpus();
  #|     return cpus.length > 0 ? cpus[0].model : null;
  #|   } catch (_) {
  #|     return null;
  #|   }
  #| }

///|
/// Logical cores from Node's `os.availableParallelism` or
/// `navigator.hardwareConcurrency`, or 0.
extern "js" fn js_logical_cores() -> Int =
  #| function() {
  #|   try {
  #|     if (typeof process !== "undefined" && typeof process.getBuiltinModule === "function") {
  #|       const os = process.getBuiltinModule("os");
  #|       if (os && typeof os.availableParallelism === "function") {
  #|         return os.availableParallelism() | 0;
  #|       }
  #|     }
  #|     if (typeof navigator !== "undefined" && typeof navigator.hardwareConcurrency === "number") {
  #|       return navigator.hardwareConcurrency | 0;
  #|     }
  #|   } catch (_) {}
  #|   return 0;
  #| }

///|
fn probe_os() -> String? {
  js_os_fact(0).bind(non_blank)
}

///|
fn probe_hostname() -> String? {
  js_os_fact(1).bind(non_blank)
}

///|
fn probe_cpu() -> String? {
  js_os_fact(2).bind(non_blank)
}

///|
fn probe_logical_cores() -> Int? {
  let count = js_logical_cores()
  if count > 0 {
    Some(count)
  } else {
    None
  }
}

///|
fn probe_git_revision() -> String? {
  None
}
