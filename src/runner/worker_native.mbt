///|
async fn[Prepared, Output, Context] collect_worker_output(
  worker : WorkerSpec[Prepared, Output, Context],
  prepared : Prepared,
  context : Context,
) -> (Int, String, String) {
  let cwd = worker.cwd.map(path => path[:])
  @async.with_task_group(group => {
    let (stdout_reader, stdout_writer) = @process.read_from_process()
    let (stderr_reader, stderr_writer) = @process.read_from_process()
    defer stdout_reader.close()
    defer stderr_reader.close()
    let process = @process.spawn(
      group,
      worker.command,
      (worker.build_arguments)(prepared, context),
      stdout=stdout_writer,
      stderr=stderr_writer,
      cwd?,
      cancel_handler=@process.hard_cancel(),
    )
    let stdout = group.spawn(() => stdout_reader.read_all().text())
    let stderr = group.spawn(() => stderr_reader.read_all().text())
    (process.wait(), stdout.wait(), stderr.wait())
  })
}
