///|
async fn main {
  let request = parse_args(@env.args())
  match request.command {
    Help => println(usage())
    Replay =>
      match request.input {
        Some(path) =>
          match load_replay_spec(path) {
            Ok(spec) =>
              match execute_replay(spec) {
                Ok(output) => println(output)
                Err(message) => println("replay error: " + message)
              }
            Err(message) => println("replay error: " + message)
          }
        None => println("replay requires [validation-failure.jsonl]")
      }
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
