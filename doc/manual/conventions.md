# Repository conventions

These rules add to the Luna-Flow documentation standard for `mare_mark`.

## Claims

Documentation describes capabilities implemented on the current branch. A
capability must not be documented as complete until code and focused tests
exercise it. Design pages state current limitations explicitly.

## Package entry points

Each documented package keeps a short `README.mbt.md` beside its source as a
package-local entry point. The manual pages carry the full API reference,
design note, and tutorial.

## Verification

[Verification](verification.md) records reproducible evidence without
overstating coverage.

## Translation

Commands, identifiers, package paths, schema names such as `mmks_1`, and
version numbers stay unchanged in every translation.
