# cli tutorial

This tutorial uses the `mare-mark` command to turn a JSONL event file into an
HTML report and to inspect, then replay, a recorded validation failure. The
commands are run from a checkout of the repository; the examples use the
fixtures in `testdata/`.

## Quick start

```sh
git clone https://github.com/Luna-Flow/mare_mark
cd mare_mark
moon run src/cli --target native -- report testdata/report/sample.jsonl report.html
```

Output:

```text
report written: /path/to/mare_mark/report.html
events: 5
elapsed: 1333.542ms
```

Open `report.html` in a browser. The elapsed value varies; it is in
microseconds despite the `ms` label.

## Everyday tasks

### Use pipes

```sh
cat testdata/report/sample.jsonl \
  | moon run src/cli --target native -- report - - > report.html
```

With `-` as output nothing else is printed, so the HTML can go straight into a
file or another tool.

### Inspect a failure before replaying it

```sh
moon run src/cli --target native -- replay testdata/replay/sample.jsonl --dry-run
```

```text
command: printf
arguments: [replayed]
timeout: 1000ms
```

Read the command. If you trust it, execute it:

```sh
moon run src/cli --target native -- replay testdata/replay/sample.jsonl --yes
```

The command runs with the recorded timeout; its stdout is printed, and a
non-zero exit or a timeout makes `mare-mark` exit with `1`.

### Produce artifacts that replay

The runner writes `validation_failure` events with the `ReplaySpec` returned by
your case's `replay` function. Make that command reproduce the failure on its
own, for example a small worker that takes the implementation id and the
minimal input. With `"Luna-Flow/mare_mark/model"` imported:

```moonbit
test "a replayable failure description" {
  let replay = (input : Int, implementation : String) => {
    @model.ReplaySpec::new("my-worker", [implementation, input.to_string()], timeout_ms=2000)
  }
  let spec = replay(0, "off-by-one")
  debug_inspect(spec.arguments, content="[\"off-by-one\", \"0\"]")
}
```

The [runner tutorial](runner.md) shows a run that produces such an event.

## Going further

- Add the report step to CI: run your benchmark, write JSONL, then
  `mare-mark report run.jsonl report.html` and upload both files.
- On other targets the command supports `report` with file paths only.

## Common pitfalls

- **Replaying from stdin.** Not supported; save the artifact to a file.
- **Forgetting `--yes`.** Without it (and without `--dry-run`) `replay` exits
  with `2` and runs nothing.
- **Extra arguments.** A third positional argument is a usage error.

## Next steps

- [cli API](../api/cli.md), [cli design](../design/cli.md).
- [report tutorial](report.md) for the report itself.
