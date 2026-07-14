# Getting Started

## Generate a report

The checked-in fixture exercises the implemented end-to-end path:

```sh
moon run src/cli --target native -- report \
  testdata/report/sample.jsonl report.html
```

The command reads observation and summary JSONL events, builds a scaling Plot
IR document, and writes a self-contained HTML file with inline SVG and CSS.

## Use packages directly

Import only the boundaries a program needs:

```moonbit nocheck
import {
  "Luna-Flow/mare_mark/model"
  "Luna-Flow/mare_mark/runner"
  "Luna-Flow/mare_mark/stats"
  "Luna-Flow/mare_mark/report"
}
```

Use `runner.run_case` for raw measurements, preserve the event stream, pass
paired arrays to `stats.compare_paired`, and construct Plot IR before calling
`report.plot_svg` or `report.html`.

## CLI boundary

The CLI intentionally handles artifacts only. `replay` reads a
`validation_failure` JSONL event and executes its captured worker command on
the native target; applications compose and execute typed cases through the
MoonBit API. This keeps argument parsing, filesystem access, and report
rendering outside the benchmark timing path.
