///|
pub enum Command {
  Replay
  Report
  Help
  Version
  Unknown(String)
}

///|
pub struct CliRequest {
  command : Command
  input : String?
  output : String?
  dry_run : Bool
  yes : Bool
  quiet : Bool
  open : Bool
  show_help : Bool
  error : String?
}

///|
fn help_requested(arguments : Array[String]) -> Bool {
  arguments.any(value => value == "--help" || value == "-h")
}

///|
pub fn parse_args(arguments : Array[String]) -> CliRequest {
  let command = if arguments.length() < 2 {
    Help
  } else {
    match arguments[1] {
      "replay" => Replay
      "report" => Report
      "--version" | "-V" => Version
      "--help" | "-h" => Help
      other => Unknown(other)
    }
  }
  if help_requested(arguments) {
    return {
      command,
      input: None,
      output: None,
      dry_run: false,
      yes: false,
      quiet: false,
      open: false,
      show_help: true,
      error: None,
    }
  }
  let values : Array[String] = []
  let mut dry_run = false
  let mut yes = false
  let mut quiet = false
  let mut open = false
  let mut error : String? = None
  for i = 2; i < arguments.length(); i = i + 1 {
    let value = arguments[i]
    if value == "--dry-run" {
      dry_run = true
    } else if value == "--yes" {
      yes = true
    } else if value == "--quiet" {
      quiet = true
    } else if value == "--open" {
      open = true
    } else if value != "-" && value.has_prefix("-") {
      error = Some("unknown option '" + value + "'")
    } else {
      values.push(value)
    }
  }
  let input = if values.length() > 0 { Some(values[0]) } else { None }
  let output = if values.length() > 1 { Some(values[1]) } else { None }
  if values.length() > 2 && error is None {
    error = Some("too many positional arguments")
  }
  { command, input, output, dry_run, yes, quiet, open, show_help: false, error }
}

///|
pub fn usage() -> String {
  "mare-mark <replay|report> [options] [input] [output]\n\nCommands:\n  report   Convert JSONL events to HTML\n  replay   Replay the command recorded in a validation_failure artifact\n\nOptions:\n  -h, --help       Show command help\n  -V, --version    Show version\n\nExamples:\n  mare-mark report events.jsonl report.html\n  mare-mark report - -\n  mare-mark replay failure.jsonl --dry-run\n\nInput may be '-' for stdin; report output may be '-' for stdout. Replay requires the native target."
}

///|
pub fn command_help(command : Command) -> String {
  match command {
    Report =>
      "mare-mark report [--quiet] [--open] <input.jsonl|-> <output.html|->\nReads JSONL events and writes a self-contained HTML report.\nUse --quiet to suppress progress; --open opens the generated report on native."
    Replay =>
      "mare-mark replay [--dry-run] [--yes] <artifact.jsonl|->\n--dry-run prints the recorded command and timeout without executing it.\nExecution requires both --yes and the native target."
    _ => usage()
  }
}

///|
pub fn report_html(document : @ir.PlotDocument) -> String {
  @report.html(document)
}

///|
pub fn render_jsonl_report(
  input_path : String,
  output_path : String,
  target? : String = "unknown",
) -> Result[String, String] {
  let source = try @fs.read_file_to_string(input_path) catch {
    _ => return Err("cannot read report input: " + input_path)
  } noraise {
    source => source
  }
  let document = match @report.document_from_jsonl(source, target~) {
    Ok(document) => document
    Err(message) => return Err(message)
  }
  try @fs.write_string_to_file(output_path, @report.html(document)) catch {
    _ => Err("cannot write report output: " + output_path)
  } noraise {
    _ => Ok(output_path)
  }
}

///|
pub fn load_replay_spec(path : String) -> Result[@model.ReplaySpec, String] {
  let source = try @fs.read_file_to_string(path) catch {
    _ => return Err("cannot read replay artifact: " + path)
  } noraise {
    source => source
  }
  replay_spec_from_jsonl(source)
}

///|
pub fn replay_spec_from_jsonl(
  source : String,
) -> Result[@model.ReplaySpec, String] {
  let mut line_number = 0
  for line_view in source.split("\n") {
    line_number += 1
    let line = line_view.to_owned().trim()
    if line == "" {
      continue
    }
    let value = try @json.parse(line) catch {
      _ => return Err("invalid JSONL at line " + line_number.to_string())
    } noraise {
      value => value
    }
    guard value is Object(object) else {
      return Err(
        "JSONL event at line " + line_number.to_string() + " is not an object",
      )
    }
    match object.get("artifact_version") {
      Some(String(version)) if version !=
        @model.ArtifactVersion::V1.identifier() =>
        return Err(
          "unsupported artifact version '" +
          version +
          "' at line " +
          line_number.to_string(),
        )
      Some(String(_)) | None => ()
      Some(_) =>
        return Err(
          "invalid artifact version at line " + line_number.to_string(),
        )
    }
    guard object.get("type") is Some(String("validation_failure")) else {
      continue
    }
    guard object.get("replay_command") is Some(String(command)) else {
      return Err(
        "validation_failure at line " +
        line_number.to_string() +
        " has no replay command",
      )
    }
    let arguments = match object.get("replay_arguments") {
      Some(Array(values)) =>
        values.filter_map(value => {
          match value {
            String(argument) => Some(argument)
            _ => None
          }
        })
      _ => []
    }
    let timeout_ms = match object.get("replay_timeout_ms") {
      Some(Number(value, ..)) => value.to_int()
      _ => 5000
    }
    return Ok(@model.ReplaySpec::new(command, arguments, timeout_ms~))
  }
  Err("no validation_failure event found")
}
