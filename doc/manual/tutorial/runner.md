# `runner` Tutorial

The common single-step path is an immutable description compiled before any
measurement effects occur:

```moonbit nocheck
let baseline = @runner.Implementation::stateless(
  "baseline", "1", input => @model.OperationResult::completed(add(input), ()),
)
let candidate = @runner.Implementation::stateless(
  "candidate", "1", input => @model.OperationResult::completed(add_fast(input), ()),
)
let plan = @runner.single_step("vector_add", scales)
  .with_immutable_input(generate, fingerprint)
  .compare([baseline, candidate])
  .against_equal(reference, (expected, actual) => expected == actual)
  .compile()
  .unwrap()
let protocol = @runner.ProtocolPreset::Development.validated()
let context = @runner.RunContext::new(environment, sink, seed, protocol)
let summary = @runner.run(plan, context)
```

Use explicit fixture, implementation, oracle, and sink combinators for stateful
or multi-step cases. Preserve emitted observations before computing summaries.

Use distinct runs for JS and native targets. Their elapsed values are not a
single comparable population.
