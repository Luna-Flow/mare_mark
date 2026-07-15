///|
fn main {
  let request = parse_args(@env.args())
  if request.show_help {
    println(command_help(request.command))
    return
  }
  match request.command {
    Help => println(usage())
    Version => println("mare-mark 0.3.0")
    Unknown(name) => {
      println(
        "mare-mark: error: unknown command '" +
        name +
        "'\nTry 'mare-mark --help' for usage.",
      )
      @sys.exit(2)
    }
    Replay => {
      println(
        "mare-mark: error: replay requires the native target\nTry 'mare-mark replay --help'.",
      )
      @sys.exit(2)
    }
    Report =>
      match (request.input, request.output) {
        (Some(input_path), Some(output_path)) =>
          match render_jsonl_report(input_path, output_path) {
            Ok(path) => println("report written: " + path)
            Err(message) => {
              println("mare-mark: error: " + message)
              @sys.exit(1)
            }
          }
        _ => {
          println("mare-mark: error: report requires input and output paths")
          @sys.exit(2)
        }
      }
  }
}
