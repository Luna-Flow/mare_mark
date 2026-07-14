///|
fn[Prepared, Output, Context] collect_worker_output(
  _worker : WorkerSpec[Prepared, Output, Context],
  _prepared : Prepared,
  _context : Context,
) -> (Int, String, String) {
  (-1, "", "subprocess workers require the native target")
}
