# mare_mark Documentation

This documentation describes the `0.3.0` implementation baseline. Generated
`pkg.generated.mbti` files are authoritative for public names and signatures.

Start with [Getting started](./getting_started.md), then read
[Architecture](./architecture.md), [Package reference](./package_reference.md),
and [Verification](./verification.md).

## Primary Package Guides

- Runner: [API](./runner/api.md), [tutorial](./runner/tutorial.md), [design](./runner/design.md)
- Statistics: [API](./stats/api.md), [tutorial](./stats/tutorial.md), [design](./stats/design.md)
- Reports: [API](./report/api.md), [tutorial](./report/tutorial.md), [design](./report/design.md)

## Package Map

| Boundary | Packages |
| --- | --- |
| Protocol and events | `model`, `event`, `ir_sink` |
| Inputs and lifecycle | `generator`, `fixture` |
| Validation and measurement | `experiment`, `runner` |
| Analysis and presentation | `stats`, `ir_model`, `report` |
| Search policies | `tune`, `tune_gemm` |
| Native file/process effects | `cli` |

## Other Packages

The [Package reference](./package_reference.md) documents the public role,
timing boundary, and stability notes for every package. Generated
`pkg.generated.mbti` snapshots remain the source of exact signatures.

## Stability

mare_mark is pre-1.0. Plot schema `mmks_1` and JSONL artifact version `mmka_1`
are explicit compatibility markers, but this version does not promise long-term
compatibility for every package type. Current limitations are stated explicitly
in each design page.
