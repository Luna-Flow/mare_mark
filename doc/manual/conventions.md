# Repository conventions

These rules add to the Luna-Flow documentation standard for `mare_mark`.

## Claims

Pages describe what the current branch implements. A capability is documented
as available only when code and focused tests exercise it. Fields and enum
cases that are recorded but not acted upon (for example `ValidationCoverage`)
are documented as such, and every design page ends with the package's
boundaries.

## Package pages

Every package, including the `cli` executable and the small `ir_sink` facade,
has an API page, a tutorial and a design page. There is no separate package
reference; the package table in the [overview](index.md) links all three
pages of each package. `report`, `runner` and `stats` also keep a short
`README.mbt.md` beside their sources as a package-local pointer to the manual.

## Examples

Runnable examples are complete `test` or `async test` blocks that show their
output with `inspect` or `debug_inspect`, and they are checked as described in
[verification](verification.md). Examples never show machine-dependent values
such as timings or decisions on real measurements.

## Units and names

Times are microseconds unless a page says otherwise, written `µs`. Relative
deltas are percentages. Schema identifiers (`mmkp_1`, `mmka_1`, `mmks_1`,
`mmks_2`, `mmkts_1`) are written exactly as they appear in artifacts.

## Translation

Commands, identifiers, package paths, schema names and version numbers stay
unchanged in every translation.
