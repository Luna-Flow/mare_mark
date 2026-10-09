///|
#cfg(target="native")
fn current_target() -> @model.ExecutionTarget {
  Native
}

///|
#cfg(target="llvm")
fn current_target() -> @model.ExecutionTarget {
  Llvm
}

///|
#cfg(target="js")
fn current_target() -> @model.ExecutionTarget {
  Js
}

///|
#cfg(target="wasm")
fn current_target() -> @model.ExecutionTarget {
  Wasm
}

///|
#cfg(target="wasm-gc")
fn current_target() -> @model.ExecutionTarget {
  WasmGc
}

///|
/// Memory management of the backend: reference counting on native, LLVM and
/// linear-memory wasm; the host garbage collector on wasm-gc and JavaScript.
fn target_gc() -> String {
  match current_target() {
    Native | Llvm | Wasm => "rc"
    WasmGc => "wasm-gc"
    Js => "js-engine"
    Custom(_) => UNKNOWN
  }
}
