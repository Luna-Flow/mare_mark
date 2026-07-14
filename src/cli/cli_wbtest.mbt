///|
test "cli parser keeps command and paths" {
  let request = parse_args(["mare-mark", "report", "run.jsonl", "report.html"])
  match request.command {
    Report => ()
    _ => abort("expected report command")
  }
  assert_true(request.input is Some("run.jsonl"))
  assert_true(request.output is Some("report.html"))
}

///|
test "replay parser restores worker command arguments and timeout" {
  let source = "{\"type\":\"validation_failure\",\"replay_command\":\"printf\",\"replay_arguments\":[\"replayed\"],\"replay_timeout_ms\":250}"
  match replay_spec_from_jsonl(source) {
    Ok(spec) => {
      assert_eq(spec.command, "printf")
      assert_true(spec.arguments == ["replayed"])
      assert_eq(spec.timeout_ms, 250)
    }
    Err(message) => abort(message)
  }
}

///|
test "benchmark execution is not exposed as a CLI command" {
  let request = parse_args(["mare-mark", "run"])
  assert_true(request.command is Help)
  assert_eq(usage(), "mare-mark <replay|report> [input] [output]")
}
