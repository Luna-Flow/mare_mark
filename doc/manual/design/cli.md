# cli design

## Design goal

Every other package is pure or confines its effects to the measurement loop.
`cli` is where files, standard streams, process execution and exit codes
live. It keeps that adapter thin, and it makes the one dangerous operation,
executing a command recorded in an artifact, explicit.

## Constraints

- Processes, standard streams and the filesystem are fully available only on
  the native target.
- Replay artifacts may come from untrusted sources and contain command lines.
- Scripts must be able to tell a broken input from a broken invocation.

## Mathematical background

The command line is a small total function from argument vectors to requests,
followed by an effectful interpreter:

$$
\text{argv} \xrightarrow{\ \texttt{parse\_args}\ } \text{CliRequest} \xrightarrow{\ \texttt{main}\ } \text{effects} \times \{0, 1, 2\}.
$$

`parse_args` never fails: every vector maps to a request, with errors recorded
in a field. This keeps the parser testable on every target and separates
"what was asked" from "what happened". Exit codes partition outcomes into
success ($0$), runtime failure ($1$: IO, invalid data, failed replay) and usage
error ($2$), so scripts can tell a broken input from a broken invocation.

## Design decisions

### Pure helpers, native effects

*Problem.* Process execution and asynchronous standard streams exist only on
the native target. *Choice.* Parsing, help texts, JSONL replay extraction and
report rendering are ordinary functions in `cli.mbt`; the native `main.mbt` is
async and uses `moonbitlang/async` for stdin, stdout and processes; other
targets get `main_unimplemented.mbt`, which supports file-to-file `report` and
rejects `replay`. *Why.* The same package builds on every target, and the logic
is tested without spawning anything.

### Guarded replay

*Problem.* A replay artifact contains a command line; executing it blindly from
a file found in an issue would run arbitrary code. *Choice.* `replay` requires
a file (no stdin), prints the command with `--dry-run`, executes only with
`--yes`, enforces the recorded timeout, and fails on a non-zero exit. *Why.*
The safe default is to look; executing is an explicit second step.

### Reading only what is needed

`replay_spec_from_jsonl` stops at the first `validation_failure` and reads only
the three replay fields, after checking the version of every line before it.
A stream with many events and one failure works, and an artifact from an
unknown version is rejected before anything runs.

### Portable reports

`report` reads the whole input, builds the document with the target label
`native`, and writes one HTML file. `-` for input or output connects it to
pipes, so it composes with other tools.

## Correctness and invariants

- `parse_args` is total and does not touch the environment.
- `replay` never executes without `--yes`, and never on a non-native target.
- Usage errors exit with `2`; runtime failures with `1`.
- `report` writes nothing when parsing the events fails.

## Alternatives rejected

- **A flag library.** Two commands and four flags do not justify a dependency.
- **Executing replays by default.** Unsafe for artifacts from elsewhere.
- **Embedding the CLI logic in `report`.** Would bring file IO into a pure
  package.

## Boundaries

- No `run` command: benchmarks are MoonBit code and are run with
  `moon test` or `moon run` of your own package.
- `--open` uses the macOS `open` command.
- `replay` reads files only, executes the first failure only, and passes the
  command directly to the process API (no shell).
- The progress line prints a microsecond value labelled `ms`.
- The version string is fixed in the source.
