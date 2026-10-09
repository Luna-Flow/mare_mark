# cli tutorial

This tutorial uses the `mare-mark` command to turn a JSONL event file into an
HTML report with paired comparisons, and to inspect, then replay, a recorded
validation failure. The
commands are run from a checkout of the repository; the examples use the
fixtures in `testdata/`.

| I want to | Use |
| --- | --- |
| turn a JSONL event file into an HTML report | `mare-mark report <input.jsonl> <output.html>` |
| see which implementation is faster | the comparison table `report` prints |
| compare against a particular implementation | `mare-mark report --baseline <id> ...` |
| use the command in a pipeline | `mare-mark report - -` |
| see what a recorded failure would run | `mare-mark replay <artifact.jsonl> --dry-run` |
| run that command again | `mare-mark replay <artifact.jsonl> --yes` |
| record failures that can be replayed | a `replay` function on the case, which fills `ReplaySpec` |

## Quick start

```sh
git clone https://github.com/Luna-Flow/mare_mark
cd mare_mark
moon run src/cli --target native -- report testdata/report/compare.jsonl report.html
```

Output:

```text
report written: /path/to/mare_mark/report.html
events: 62
elapsed: 11.138ms
Comparisons
Decision threshold ±2 % and outlier policy tukey_fence (applied to the paired deltas) from the recorded protocol; run seed 42 from the record. Each row pairs the confirmatory observations of one block, needs at least 3 usable blocks, and reports a 95 % percentile bootstrap interval of the median paired delta with 10000 resamples (report defaults), seeded from the run seed, case, scale, baseline and candidate; with few blocks its actual coverage can be well below the nominal level.
case        scale  baseline  candidate  baseline µs/op  candidate µs/op  delta      95 % interval           decision    blocks used / incomplete / outliers  seed                  reason
vector-add  1024   scalar    unrolled   10.169          10.231           +0.601 %   [+0.099 %, +1.025 %]    Equivalent  7 / 0 / 1                            13588634248935341968
vector-add  1024   scalar    simd       10.14           7.091            -29.664 %  [-30.665 %, -28.754 %]  Faster      7 / 0 / 1                            2598104397583004044
vector-add  4096   scalar    unrolled   40.62           40.762           +0.594 %   [+0.099 %, +1.026 %]    Equivalent  8 / 0 / 0                            297697883029165748
vector-add  4096   scalar    simd       40.101          28.07            -29.795 %  [-30.829 %, -29.079 %]  Faster      6 / 1 / 1                            13674140354933674792
```

Open `report.html` in a browser. The elapsed time, in milliseconds, varies;
everything else is computed from the record and is the same on every machine.

`compare.jsonl` is a run of three implementations of a vector addition at two
sizes under a hierarchical design: per size, one exploratory and four
confirmatory datasets of two blocks each, a recorded threshold of 2 % and the
Tukey fence. Read a
row from left to right: the baseline and candidate medians, the median paired
delta in percent of the baseline, its 95 % bootstrap interval, the decision,
and how many blocks were used, were incomplete (an observation missing) and
were removed as outliers of the paired deltas. `simd` is about 30 % faster at
both sizes; `unrolled` is within the 2 % threshold, so `Equivalent`, although
its whole interval lies above zero. The decision compares the point estimate
with the threshold; the interval says how stable that estimate is.

## Everyday tasks

### Use pipes

```sh
cat testdata/report/sample.jsonl \
  | moon run src/cli --target native -- report - - > report.html
```

With `-` as output the HTML is the only thing on stdout, so it can go straight
into a file or another tool; the comparison table goes to stderr. Add
`--quiet` to suppress the table as well.

### Choose the baseline

By default every implementation is compared with the first one that appears
in each case. Name another one with `--baseline`:

```sh
moon run src/cli --target native -- report --baseline simd testdata/report/compare.jsonl report.html
```

Every row then has `simd` as baseline, and the signs flip: `scalar` and
`unrolled` are `Slower`. A name that is not in the record is an error that
lists the implementations it contains:

```text
mare-mark: error: unknown baseline 'avx'; implementations in the record: scalar, simd, unrolled
Check the --baseline value.
```

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
  `mare-mark report run.jsonl report.html`, keep the printed table in the job
  log, and upload both files.
- On other targets the command supports `report` with file paths only and
  does not print the table.
- Records written before the summary carried a protocol and a seed are
  compared with a 1 % threshold, no outlier filter and seed 0; the first line
  of the note says so.

## Common pitfalls

- **Replaying from stdin.** Not supported; save the artifact to a file.
- **Forgetting `--yes`.** Without it (and without `--dry-run`) `replay` exits
  with `2` and runs nothing.
- **Extra arguments.** A third positional argument is a usage error.
- **An option after `--baseline`.** `--baseline` takes the next argument as
  the id, so `--baseline --quiet` compares with an implementation called
  `--quiet`; write the id right after the option.
- **Forgetting the artifact.** `replay` needs an artifact path even with
  `--dry-run`; without one it exits with `2`.

## Next steps

- [cli API](../api/cli.md), [cli design](../design/cli.md).
- [report tutorial](report.md) for the report itself.
