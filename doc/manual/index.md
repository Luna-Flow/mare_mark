# mare_mark

This documentation describes the `0.3.0` implementation baseline. Generated
`pkg.generated.mbti` files are authoritative for public names and signatures.

Start with [Getting started](getting_started.md), then read
[Architecture](architecture.md), [Package reference](package_reference.md),
and [Verification](verification.md).

## Package map

| Boundary | Packages |
| --- | --- |
| Protocol and events | `model`, `event`, `ir_sink` |
| Inputs and lifecycle | `generator`, `fixture` |
| Validation and measurement | `experiment`, [`runner`](api/runner.md) |
| Analysis and presentation | [`stats`](api/stats.md), `ir_model`, [`report`](api/report.md) |
| Search policies | `tune`, `tune_gemm` |
| Native file/process effects | `cli` |

The primary packages `runner`, `stats`, and `report` each have an API
reference, a design note, and a tutorial. The
[Package reference](package_reference.md) documents the public role, timing
boundary, and stability notes for every package. Generated
`pkg.generated.mbti` snapshots remain the source of exact signatures.

## Stability

mare_mark is pre-1.0. Plot schema `mmks_1` and JSONL artifact version `mmka_1`
are explicit compatibility markers, but this version does not promise long-term
compatibility for every package type. Current limitations are stated explicitly
in each design page.
