# Documentation Standard

Documentation must describe the current branch rather than planned APIs.

## Structure

- Localized documentation lives under `doc/en_US`, `doc/zh_CN`, and `doc/ja_JP`.
- English is the structural baseline; translations keep matching relative paths.
- Each documented package uses `api.md`, `design.md`, and `tutorial.md`.
- `README.mbt.md` gives a short package-local entry point.
- `pkg.generated.mbti` is authoritative for MoonBit public signatures.

## Responsibilities

- `api.md` lists callable behavior and observable results.
- `tutorial.md` shows the shortest realistic workflow.
- `design.md` records ownership, invariants, effects, and explicit limitations.
- `verification.md` records reproducible evidence without overstating coverage.

Commands, identifiers, package paths, schema names, and version numbers remain
unchanged across translations. A capability must not be documented as complete
until code and focused tests exercise it.

