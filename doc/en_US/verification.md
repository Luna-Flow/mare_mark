# Verification

Verification is layered: compile the public surface, run focused package tests,
then execute the cross-target suite and smoke artifacts.

## Fast loop

```sh
moon check --target native
moon test src/model --target native
moon test src/runner --target native
moon test src/report --target native
moon fmt --check
```

## Cross-target matrix

```sh
moon test --target native
moon test --target js
moon check --target native
moon check --target js
moon info
```

Native covers process workers, monotonic timing, and replay. JS catches
serialization and pure-policy portability regressions.

## Artifact smoke tests

```sh
tmpdir=$(mktemp -d)
moon run src/cli --target native -- report \
  testdata/report/sample.jsonl "$tmpdir/report.html"
moon run src/cli --target native -- replay \
  testdata/replay/sample.jsonl --dry-run
test -s "$tmpdir/report.html"
```

The report fixture verifies JSONL parsing, scaling projection, escaping, and
self-contained output. The replay fixture verifies artifact-version checks,
command restoration, and timeout display without executing a process.

## Evidence boundaries

- `stats` tests prove deterministic percentile bootstrap bounds and reject
  invalid configuration; they do not claim BCa or hierarchical resampling.
- `runner` tests prove setup/timing ordering, balanced blocks, worker timeout,
  and typed failure preservation; they do not prove a machine's timer quality.
- `report` tests prove Plot IR and escaping invariants; they do not guarantee
  browser-specific typography or CSS rendering.
- `tune_gemm` tests prove candidate validity and numerical checks; they do not
  prove that a candidate is fastest on every CPU or target.

## Coverage and generated interfaces

```sh
moon coverage analyze
moon info
```

`pkg.generated.mbti` snapshots are the public-interface evidence. If a public
signature changes, update the generated snapshot through MoonBit tooling and
then update the matching package reference and localized index. Do not hand
edit generated files.
