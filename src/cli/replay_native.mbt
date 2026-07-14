///|
async fn execute_replay(spec : @model.ReplaySpec) -> Result[String, String] {
  let result = try
    @async.with_timeout_opt(spec.timeout_ms, () => {
      @process.collect_output(spec.command, spec.arguments)
    })
  catch {
    error => return Err("cannot start replay: " + @debug.to_string(error))
  } noraise {
    result => result
  }
  match result {
    None => Err("replay timed out after " + spec.timeout_ms.to_string() + "ms")
    Some((exit_code, stdout, stderr)) =>
      if exit_code == 0 {
        Ok(stdout.text())
      } else {
        Err(
          "replay exited " +
          exit_code.to_string() +
          (if stderr.text() == "" { "" } else { ": " + stderr.text() }),
        )
      }
  }
}
