# Verification

This page lists how the repository's claims are checked, and what each check
does not prove.

## Fast loop

```sh
moon check --target native
moon test --target native
moon fmt
moon info
```

`moon info` regenerates every `pkg.generated.mbti`; a diff in those files is a
change of the public interface and must be reflected in the API pages.

## Cross-target matrix

```sh
moon check --target all
moon test --target native
moon test --target js
moon test --target wasm
moon test --target wasm-gc
```

| Target | What runs |
| --- | --- |
| native | every test, including subprocess workers and timeouts (`#cfg(target="native")`) |
| js, wasm | every test except the native-only worker test |
| wasm-gc | the synchronous tests; `async test`s of `runner` are skipped because `moonbitlang/async` has no wasm-gc runtime |

Native-only source files are selected per target in `moon.pkg`
(`worker_native.mbt`, `main.mbt`, `replay_native.mbt`); the packages that
contain them silence `unused_package` because some imports are used only on
native. `moon check --target all` must produce no warning.

## Artifact smoke tests

```sh
tmpdir=$(mktemp -d)
moon run src/cli --target native -- report testdata/report/sample.jsonl "$tmpdir/report.html"
test -s "$tmpdir/report.html"
moon run src/cli --target native -- replay testdata/replay/sample.jsonl --dry-run
```

The report fixture checks JSONL parsing, the scaling projection and the
self-contained output. The replay fixture checks artifact parsing, command
restoration and the timeout display without executing anything. CI runs the
same commands, a coverage budget (`moon coverage analyze`, at most 360
uncovered lines), the interface check (`moon info` with no diff) and
`moon fmt --check`.

## Documentation examples

Every `moonbit` block in `doc/manual` is a complete test or a top-level
definition; blocks that are deliberately partial are fenced
`moonbit nocheck`. To check them, put each page's blocks into one package of a
scratch module outside the repository that imports the mare_mark packages
(with `moonbitlang/async` for the `async test`s), join it with the repository
in a `moon.work`, and run `moon test`. The `inspect` contents in the pages are
the verified outputs. Outputs that depend on the machine (timings, decisions on
real measurements) are never shown.

The catalogs and attachments are checked with the Luna-Flow `lunadoc` tool:
`lunadoc check --compile` (links, catalogs, Typst attachments) and
`lunadoc status` (translation coverage).

## What the tests prove, and what they do not

- `stats`: robust summaries, decision thresholds, invalid-input errors, and
  that bootstrap intervals are deterministic and lie within the range of the
  deltas. Not: coverage of the intervals, BCa or hierarchical resampling.
- `runner`: validation before timing, timing boundaries per setup policy
  (synchronization, reset exclusion), calibration bounds, balanced order,
  worker abort and timeout, minimized replayable failures, relational
  mismatches, outcome counting. Not: the quality of a machine's timer or the
  absence of interference from other processes.
- `report`: projection rules, escaping, version gating, self-contained
  output. Not: rendering in a particular browser.
- `tune` and `tune_gemm`: median scoring, order-independent selection, Pareto
  filtering, candidate constraints, bitwise agreement of blocked and reference
  GEMM over all layouts with tails. Not: that a tuned candidate is fastest on
  another CPU.
- `cli`: argument parsing, help texts, replay extraction. The native `main` is
  exercised by the smoke tests only.
