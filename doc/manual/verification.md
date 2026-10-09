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
| native | every test, including subprocess workers and timeouts and the host probes of `env_detect` (`#cfg(target="native")`) |
| js, wasm | every test except the native-only worker and probe tests; `env_detect` checks its Node.js probe or its environment-variable fallback |
| wasm-gc | the synchronous tests; `async test`s of `runner` and `env_detect` are skipped because `moonbitlang/async` has no wasm-gc runtime |

Target-specific source files are selected per target in `moon.pkg`
(`worker_native.mbt`, `main.mbt`, `replay_native.mbt`, and `probe_native.mbt`,
`probe_js.mbt` or `probe_none.mbt` in `env_detect`); the packages that
contain them silence `unused_package` because some imports are used only on
one target. `moon check --target all` must produce no warning.

## Artifact smoke tests

```sh
tmpdir=$(mktemp -d)
moon run src/cli --target native -- report testdata/report/sample.jsonl "$tmpdir/report.html"
test -s "$tmpdir/report.html"
moon run src/cli --target native -- report --baseline scalar testdata/report/compare.jsonl "$tmpdir/compare.html" > "$tmpdir/compare.txt"
grep -q 'decision-faster' "$tmpdir/compare.html"
grep -q 'Faster' "$tmpdir/compare.txt"
moon run src/cli --target native -- replay testdata/replay/sample.jsonl --dry-run
```

`sample.jsonl` is an old-style record without phases, scales, blocks or a
protocol; it checks JSONL parsing, the `dataset_id` fallback of the scaling
projection, the stated comparison defaults and the self-contained output.
`compare.jsonl` is a hierarchical-design record with a protocol, several
confirmatory blocks per scale, an incomplete block and a paired-delta outlier;
it checks the comparisons in the HTML and in the printed table. The replay
fixture checks artifact parsing, command restoration and the timeout display
without executing anything. CI runs the
same commands, a coverage budget (`moon coverage analyze`, at most 360
uncovered lines), the interface check (`moon info` with no diff) and
`moon fmt --check`.

## Documentation examples

Every `moonbit` block in `doc/manual` is a complete test or a top-level
definition; blocks that are deliberately partial are fenced
`moonbit nocheck`. To check them, put each page's blocks into one temporary
package that imports the mare_mark packages it uses (with `moonbitlang/async`
for the `async test`s), either under `src/` or in a scratch module joined with
the repository in a `moon.work`, and run `moon test` on it. The `cli` pages
are tests of the executable package, so their blocks go into a temporary
`_test.mbt` file of `src/cli`. Remove the temporary package or file
afterwards. The `inspect` contents in the pages are
the verified outputs. Outputs that depend on the machine (timings, decisions on
real measurements) are never shown.

The catalogs and attachments are checked with the Luna-Flow `lunadoc` tool:
`lunadoc check --compile` (links, catalogs, Typst attachments) and
`lunadoc status` (translation coverage).

## What the tests prove, and what they do not

- `stats`: robust summaries, decision thresholds, invalid-input errors, and
  that bootstrap intervals are deterministic and lie within the range of the
  deltas, the decision for ties and for thresholds that are `0`, `NaN`,
  infinite or negative, and `NaN` propagation through `summarize` and
  `compare_paired`. Not: coverage of the intervals (the design page computes
  it for small samples), BCa or hierarchical resampling.
- `model` and `event`: that every protocol field changes the identity, the
  published FNV-1a test vectors, run-id escaping, and that the `protocol`
  object round-trips through JSON text for every variant and edge value. Not:
  freedom from 64-bit digest collisions.
- `runner`: validation before timing, timing boundaries per setup policy
  (synchronization, reset exclusion), calibration bounds, balanced order,
  the dataset and event sequence of each experiment design (snapshots of the
  fixed design, unique dataset ids, the block-to-dataset mapping), each
  validation coverage, the `repeats_per_dataset` rules, the rejection of
  `PerRun` setup with several datasets, worker abort and timeout, minimized
  replayable failures, relational mismatches, outcome counting. Not: the
  quality of a machine's timer or the absence of interference from other
  processes.
- `env_detect`: the target and GC labels, the timestamp and run-id formats
  (including leap days and the `seq<n>` fallback), that overrides win and
  that a field is undetected exactly when it holds its fallback, the
  `/proc/cpuinfo` parser and the subprocess wrapper on native. Not: that a
  particular host's probes succeed.
- `report`: projection rules (confirmatory only, medians per scale, linear
  and categorical axes, the `dataset_id` fallback), pairing by block,
  incomplete and outlier counts, the outlier policy on paired deltas, the
  recorded and default settings, row seeds, decisions and reasons of every
  `Unknown` and `Invalid` case, escaping, version gating, self-contained
  output. Not: rendering in a particular browser, or the coverage of the
  intervals.
- `tune` and `tune_gemm`: median scoring, order-independent selection, Pareto
  filtering, candidate constraints, bitwise agreement of blocked and reference
  GEMM over all layouts with tails. Not: that a tuned candidate is fastest on
  another CPU. `seeded_order` is tested for spreading ids that differ only at
  the end, not for statistical randomness.
- `cli`: argument parsing (including `--baseline`), help texts, replay
  extraction, where the comparison table goes. The native `main` is exercised
  by the smoke tests only.
