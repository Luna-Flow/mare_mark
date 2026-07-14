///|
pub enum Command {
  Replay
  Report
  Help
}

///|
pub struct CliRequest {
  command : Command
  input : String?
  output : String?
}

///|
pub fn parse_args(arguments : Array[String]) -> CliRequest {
  if arguments.length() < 2 {
    { command: Help, input: None, output: None }
  } else {
    let command = match arguments[1] {
      "replay" => Replay
      "report" => Report
      _ => Help
    }
    let input = if arguments.length() > 2 { Some(arguments[2]) } else { None }
    let output = if arguments.length() > 3 { Some(arguments[3]) } else { None }
    { command, input, output }
  }
}

///|
pub fn usage() -> String {
  "mare-mark <replay|report> [input] [output]"
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
  for line_view in source.split("\n") {
    let line = line_view.to_owned().trim()
    if line == "" {
      continue
    }
    let value = try @json.parse(line) catch {
      _ => continue
    } noraise {
      value => value
    }
    guard value is Object(object) else { continue }
    guard object.get("type") is Some(String("validation_failure")) else {
      continue
    }
    guard object.get("replay_command") is Some(String(command)) else {
      return Err("validation failure has no replay command")
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
