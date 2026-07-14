///|
fn main {
  let request = parse_args(@env.args())
  match request.command {
    Help => println(usage())
    Replay =>
      println(
        "replay requires --target native: " + request.input.unwrap_or("<input>"),
      )
    Report =>
      match (request.input, request.output) {
        (Some(input_path), Some(output_path)) =>
          match render_jsonl_report(input_path, output_path) {
            Ok(path) => println("report written: " + path)
            Err(message) => println("report error: " + message)
          }
        _ => println("report requires [input.jsonl] [output.html]")
      }
  }
}
