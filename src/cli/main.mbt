///|
async fn write_stderr(message : String) -> Unit {
  @stdio.stderr.write(message + "\n")
}

///|
async fn write_stdout(message : String) -> Unit {
  @stdio.stdout.write(message + "\n")
}

///|
/// The usage error of a `replay` request, as a message and a hint, or `None`
/// when the request may proceed. Checked in this order: parse errors, a
/// missing artifact (with or without `--dry-run`), stdin as input, and a
/// missing `--yes` outside `--dry-run`.
fn replay_usage_error(request : CliRequest) -> (String, String)? {
  match request.error {
    Some(message) => return Some((message, "Try 'mare-mark replay --help'."))
    None => ()
  }
  match request.input {
    None =>
      Some(
        ("replay requires an input artifact", "Try 'mare-mark replay --help'."),
      )
    Some("-") =>
      Some(
        (
          "replay stdin is not available on this command path yet", "Use a file artifact with 'mare-mark replay --help'.",
        ),
      )
    Some(_) =>
      if request.yes == false && request.dry_run == false {
        Some(
          (
            "replay requires --yes to execute an external command", "Use --dry-run to inspect it first.",
          ),
        )
      } else {
        None
      }
  }
}

///|
/// Formats a duration measured in microseconds as milliseconds.
fn elapsed_text(elapsed_us : Double) -> String {
  (elapsed_us / 1000.0).to_string() + "ms"
}

///|
async fn main {
  let request = parse_args(@env.args())
  if request.show_help {
    write_stdout(command_help(request.command))
    return
  }
  match request.command {
    Help => write_stdout(usage())
    Version => write_stdout("mare-mark 0.3.0")
    Unknown(name) => {
      write_stderr(
        "mare-mark: error: unknown command '" +
        name +
        "'\nTry 'mare-mark --help' for usage.",
      )
      @sys.exit(2)
    }
    Replay => {
      match replay_usage_error(request) {
        Some((message, hint)) => {
          write_stderr("mare-mark: error: " + message + "\n" + hint)
          @sys.exit(2)
        }
        None => ()
      }
      match request.input {
        None => ()
        Some(path) =>
          match load_replay_spec(path) {
            Err(message) => {
              write_stderr(
                "mare-mark: error: " +
                message +
                "\nCheck the artifact path and JSONL format.",
              )
              @sys.exit(1)
            }
            Ok(spec) => {
              let display = "command: " +
                spec.command +
                "\narguments: [" +
                spec.arguments.join(", ") +
                "]\ntimeout: " +
                spec.timeout_ms.to_string() +
                "ms"
              if request.dry_run {
                write_stdout(display)
              } else {
                match execute_replay(spec) {
                  Ok(output) => write_stdout(output)
                  Err(message) => {
                    write_stderr(
                      "mare-mark: error: " +
                      message +
                      "\nCheck the recorded command and timeout.",
                    )
                    @sys.exit(1)
                  }
                }
              }
            }
          }
      }
    }
    Report => {
      if request.error is Some(message) {
        write_stderr(
          "mare-mark: error: " + message + "\nTry 'mare-mark report --help'.",
        )
        @sys.exit(2)
      }
      match (request.input, request.output) {
        (Some(input_path), Some(output_path)) => {
          let start = @bench.monotonic_clock_start()
          let source = if input_path == "-" {
            @stdio.stdin.read_all().text()
          } else {
            try @fs.read_file_to_string(input_path) catch {
              _ => {
                write_stderr(
                  "mare-mark: error: cannot read report input: " +
                  input_path +
                  "\nCheck that the file exists and is readable.",
                )
                @sys.exit(1)
                ""
              }
            } noraise {
              source => source
            }
          }
          let events = source
            .split("\n")
            .filter(line => line.trim() != "")
            .length()
          match @report.document_from_jsonl(source, target="native") {
            Err(message) => {
              write_stderr(
                "mare-mark: error: " +
                message +
                "\nCheck that every input line is valid JSONL.",
              )
              @sys.exit(1)
            }
            Ok(document) => {
              let html = @report.html(document)
              if output_path == "-" {
                @stdio.stdout.write(html)
              } else {
                let absolute = @path.Path::resolve(output_path).to_string()
                try @fs.write_string_to_file(absolute, html) catch {
                  _ => {
                    write_stderr(
                      "mare-mark: error: cannot write report output: " +
                      absolute +
                      "\nCheck directory permissions.",
                    )
                    @sys.exit(1)
                  }
                } noraise {
                  _ => ()
                }
                if request.open {
                  ignore(@process.run("open", [absolute]))
                }
                if request.quiet == false {
                  let elapsed = @bench.monotonic_clock_end(start)
                  write_stdout(
                    "report written: " +
                    absolute +
                    "\nevents: " +
                    events.to_string() +
                    "\nelapsed: " +
                    elapsed_text(elapsed),
                  )
                }
              }
            }
          }
        }
        _ => {
          write_stderr(
            "mare-mark: error: report requires input and output paths\nTry 'mare-mark report --help'.",
          )
          @sys.exit(2)
        }
      }
    }
  }
}
