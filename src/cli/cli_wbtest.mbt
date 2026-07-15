///|
test "cli parser keeps command and paths" {
  let request = parse_args(["mare_mark", "report", "run.jsonl", "report.html"])
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
test "unknown commands remain distinguishable from help" {
  let request = parse_args(["mare_mark", "run"])
  assert_true(request.command is Unknown("run"))
  assert_true(usage().contains("mare-mark <replay|report>"))
}

///|
test "subcommand help is recognized without positional validation" {
  let report = parse_args(["mare-mark", "report", "--help"])
  assert_true(report.command is Report)
  assert_true(report.show_help)
  assert_true(command_help(report.command).contains("mare-mark report"))
}

///|
test "unknown options are parse errors" {
  let request = parse_args(["mare-mark", "report", "--wat"])
  assert_true(request.error is Some("unknown option '--wat'"))
}

///|
test "dash remains a positional stdin or stdout path" {
  let request = parse_args(["mare-mark", "report", "-", "-"])
  assert_true(request.input is Some("-"))
  assert_true(request.output is Some("-"))
  assert_true(request.error is None)
}

///|
test "command flags and excess positionals are validated" {
  let replay = parse_args([
    "mare-mark", "replay", "--dry-run", "--yes", "failure.jsonl",
  ])
  assert_true(replay.dry_run)
  assert_true(replay.yes)
  let report = parse_args([
    "mare-mark", "report", "--quiet", "--open", "in.jsonl", "out.html",
  ])
  assert_true(report.quiet)
  assert_true(report.open)
  let excess = parse_args([
    "mare-mark", "report", "in.jsonl", "out.html", "extra",
  ])
  assert_true(excess.error is Some("too many positional arguments"))
}

///|
test "replay parser reports malformed and incomplete artifacts" {
  assert_true(
    replay_spec_from_jsonl("") is Err("no validation_failure event found"),
  )
  assert_true(
    replay_spec_from_jsonl("not-json") is Err("invalid JSONL at line 1"),
  )
  assert_true(
    replay_spec_from_jsonl("[]")
    is Err("JSONL event at line 1 is not an object"),
  )
  assert_true(
    replay_spec_from_jsonl("{\"type\":\"validation_failure\"}")
    is Err("validation_failure at line 1 has no replay command"),
  )
  assert_true(
    replay_spec_from_jsonl(
      "{\"artifact_version\":\"mmka_99\",\"type\":\"validation_failure\"}",
    )
    is Err("unsupported artifact version 'mmka_99' at line 1"),
  )
}
