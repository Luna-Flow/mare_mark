# cli API

`Luna-Flow/mare_mark/cli` is the `mare-mark` executable: it renders JSONL
event files as HTML reports and replays recorded validation failures. This
page documents the command line and the public helper functions of the
package. See the [cli design](../design/cli.md).

Source: [`src/cli/cli.mbt`](../../../src/cli/cli.mbt),
[`src/cli/main.mbt`](../../../src/cli/main.mbt) (native),
[`src/cli/main_unimplemented.mbt`](../../../src/cli/main_unimplemented.mbt)
(other targets), [`src/cli/replay_native.mbt`](../../../src/cli/replay_native.mbt).

## Command line

Run it from a checkout with `moon run src/cli --target native -- <arguments>`.

```text
mare-mark <replay|report> [options] [input] [output]
```

| Invocation | Effect |
| --- | --- |
| `mare-mark report <input.jsonl> <output.html>` | parse the events and write a self-contained HTML report |
| `mare-mark report - -` | read events from stdin, write HTML to stdout |
| `mare-mark report --quiet ...` | do not print the progress summary |
| `mare-mark report --open ...` | open the written file with `open` (macOS) |
| `mare-mark replay <artifact.jsonl> --dry-run` | print the command, arguments and timeout of the first `validation_failure` |
| `mare-mark replay <artifact.jsonl> --yes` | execute that command with its timeout and print its stdout |
| `mare-mark --version`, `-V` | print `mare-mark 0.3.0` |
| `mare-mark --help`, `-h`, or no arguments | print usage; with a command, print that command's help |

Options may appear anywhere after the command. Unknown options and more than
two positional arguments are errors. `replay` refuses `-` as input and refuses
to execute without `--yes`.

Exit codes: `0` on success, `1` when a file cannot be read or written, the
JSONL is invalid, or a replay fails or times out, and `2` for usage errors
(unknown command or option, missing arguments, missing `--yes`). On targets
other than native, `report` works through `render_jsonl_report`, and `replay`
exits with `2`.

After writing a file, `report` prints the absolute output path, the number of
non-empty input lines and the elapsed time. The elapsed value is measured in
microseconds but labelled `ms`.

## Package functions

The package is an executable (`pkgtype(kind: "executable")`). Its public
functions are the building blocks of `main` and are covered by the package's
tests. MoonBit 0.10 still lets another package import an executable package,
but warns that this will become an error, so do not build on these functions
from your own packages.

## Requests

### `Command`

`Command` is the subcommand selected by the first argument.

```mbti
pub enum Command {
  Replay
  Report
  Help
  Version
  Unknown(String)
}
```

### `CliRequest`

`CliRequest` is the parsed command line.

```mbti
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
```

`input` and `output` are the first two positional arguments. `error` holds the
first usage error (`"unknown option '…'"`, `"too many positional arguments"`).

### `parse_args`

`parse_args` parses a full argument vector, including the program name.

```mbti
pub fn parse_args(Array[String]) -> CliRequest
```

Index 1 selects the command (`replay`, `report`, `--version`/`-V`,
`--help`/`-h`; fewer than two arguments give `Help`). If `--help` or `-h`
appears anywhere, the result only has `show_help = true` and the command.
Otherwise arguments from index 2 on are flags (`--dry-run`, `--yes`,
`--quiet`, `--open`), positionals, or errors; `-` counts as a positional.

```moonbit
test "parse a report command" {
  let request = @cli.parse_args(["mare-mark", "report", "--quiet", "events.jsonl", "report.html"])
  inspect(request.command is Report, content="true")
  inspect(request.input == Some("events.jsonl"), content="true")
  inspect(request.quiet, content="true")
  let wrong = @cli.parse_args(["mare-mark", "report", "--fast", "a", "b"])
  inspect(wrong.error == Some("unknown option '--fast'"), content="true")
}
```

### `usage`, `command_help`

`usage` returns the general help text; `command_help` returns the help of
`Report` or `Replay`, and `usage()` for other commands.

```mbti
pub fn usage() -> String
pub fn command_help(Command) -> String
```

## Reports

### `render_jsonl_report`

`render_jsonl_report` reads a JSONL file, renders it and writes the HTML.

```mbti
pub fn render_jsonl_report(String, String, target? : String) -> Result[String, String]
```

Arguments: input path, output path, and the target label (default
`"unknown"`). Returns the output path, or an error message for an unreadable
input, invalid events or an unwritable output.

### `report_html`

`report_html` is `@report.html`.

```mbti
pub fn report_html(@ir_model.PlotDocument) -> String
```

## Replay

### `replay_spec_from_jsonl`

`replay_spec_from_jsonl` extracts the replay command of the first
`validation_failure` event in a JSONL text.

```mbti
pub fn replay_spec_from_jsonl(String) -> Result[@model.ReplaySpec, String]
```

Lines before it are checked for valid JSON objects and a supported
`artifact_version`, and otherwise skipped. The event must have a string
`replay_command`; `replay_arguments` keeps its string elements, and
`replay_timeout_ms` defaults to `5000`. Errors: invalid JSON, a non-object
line, an unsupported version, a missing command, or no failure event at all.

```moonbit
test "read a replay artifact" {
  let artifact =
    #|{"type":"observation","implementation":"a","dataset_id":0,"elapsed_us":1.0}
    #|{"type":"validation_failure","replay_command":"worker","replay_arguments":["fast","42"],"replay_timeout_ms":250}
  let spec = @cli.replay_spec_from_jsonl(artifact).unwrap()
  inspect(spec.command, content="worker")
  debug_inspect(spec.arguments, content="[\"fast\", \"42\"]")
  inspect(spec.timeout_ms, content="250")
  inspect(@cli.replay_spec_from_jsonl("") is Err("no validation_failure event found"), content="true")
}
```

### `load_replay_spec`

`load_replay_spec` reads a file and calls `replay_spec_from_jsonl`.

```mbti
pub fn load_replay_spec(String) -> Result[@model.ReplaySpec, String]
```
