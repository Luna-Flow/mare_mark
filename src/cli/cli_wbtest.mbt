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

///|
#cfg(target="native")
test "replay without an artifact is a usage error, also with --dry-run" {
  for
    arguments in [
      ["mare-mark", "replay"],
      ["mare-mark", "replay", "--dry-run"],
      ["mare-mark", "replay", "--yes"],
    ] {
    guard replay_usage_error(parse_args(arguments)) is Some((message, _)) else {
      abort("expected a usage error")
    }
    assert_eq(message, "replay requires an input artifact")
  }
  assert_true(
    replay_usage_error(
      parse_args(["mare-mark", "replay", "a.jsonl", "--dry-run"]),
    )
    is None,
  )
  assert_true(
    replay_usage_error(parse_args(["mare-mark", "replay", "a.jsonl"]))
    is Some(("replay requires --yes to execute an external command", _)),
  )
  assert_true(
    replay_usage_error(parse_args(["mare-mark", "replay", "-", "--yes"]))
    is Some(("replay stdin is not available on this command path yet", _)),
  )
}

///|
#cfg(target="native")
test "report elapsed time converts microseconds to milliseconds" {
  assert_eq(elapsed_text(1177.958), "1.177958ms")
  assert_eq(elapsed_text(2500.0), "2.5ms")
}

///|
test "report accepts a baseline implementation" {
  let request = parse_args([
    "mare-mark", "report", "--baseline", "scalar", "--quiet", "in.jsonl", "out.html",
  ])
  assert_true(request.baseline is Some("scalar"))
  assert_true(request.quiet)
  assert_true(request.input is Some("in.jsonl"))
  assert_true(request.output is Some("out.html"))
  assert_true(request.error is None)
  let inline = parse_args(["mare-mark", "report", "--baseline=simd", "-", "-"])
  assert_true(inline.baseline is Some("simd"))
  assert_true(inline.output is Some("-"))
  let missing = parse_args(["mare-mark", "report", "in.jsonl", "--baseline"])
  assert_true(
    missing.error is Some("option '--baseline' requires an implementation id"),
  )
  assert_true(parse_args(["mare-mark", "report"]).baseline is None)
  assert_true(command_help(Report).contains("--baseline <id>"))
  assert_true(usage().contains("--baseline scalar"))
}

///|
#cfg(target="native")
test "report prints the comparison table unless quiet" {
  let lines = []
  for block = 0; block < 3; block = block + 1 {
    for implementation in ["base", "fast"] {
      lines.push(
        "{\"type\":\"observation\",\"case\":\"c\",\"implementation\":\"" +
        implementation +
        "\",\"dataset_id\":0,\"block_id\":" +
        block.to_string() +
        ",\"scale\":\"8\",\"elapsed_us\":" +
        (if implementation == "base" { "10" } else { "5" }) +
        "}",
      )
    }
  }
  let source = lines.join("\n")
  guard @report.document_from_jsonl(source) is Ok(document) else {
    abort("document")
  }
  guard report_comparison_output(document, "out.html", false)
    is Some((text, false)) else {
    abort("expected the table on stdout")
  }
  assert_true(text.has_prefix("Comparisons\n"))
  assert_true(text.contains("base      fast"))
  assert_true(text.contains("Faster"))
  assert_true(report_comparison_output(document, "-", false) is Some((_, true)))
  assert_true(report_comparison_output(document, "-", true) is None)
  guard @report.document_from_jsonl(source, baseline="fast") is Ok(swapped) else {
    abort("document")
  }
  guard report_comparison_output(swapped, "out.html", false) is Some((text, _)) else {
    abort("expected a table")
  }
  assert_true(text.contains("fast      base") && text.contains("Slower"))
  let single = @report.document_from_jsonl(lines[0]).unwrap()
  assert_true(report_comparison_output(single, "out.html", false) is None)
}
