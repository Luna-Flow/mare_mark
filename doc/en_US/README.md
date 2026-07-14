# Mare Mark Documentation

This documentation describes the `0.1.0` implementation baseline. Generated
`pkg.generated.mbti` files are authoritative for public names and signatures.

Start with [Getting started](./getting_started.md), then read
[Architecture](./architecture.md) and [Verification](./verification.md).

## Primary Package Guides

- Runner: [API](./runner/api.md), [tutorial](./runner/tutorial.md), [design](./runner/design.md)
- Statistics: [API](./stats/api.md), [tutorial](./stats/tutorial.md), [design](./stats/design.md)
- Reports: [API](./report/api.md), [tutorial](./report/tutorial.md), [design](./report/design.md)

## Other Packages

`model`, `generator`, `fixture`, `event`, `ir_sink`, `experiment`, `ir_model`,
`tune`, `tune_gemm`, and `cli` are summarized in the architecture guide.
Package-local guides will be added only as their documented surfaces mature.

## Stability

Mare Mark is pre-1.0. Plot schema `mmk-plot-v2` and emitted JSONL fields are
versioned artifacts, but this version does not promise long-term compatibility
for every package type. Current limitations are stated explicitly in each
design page.
