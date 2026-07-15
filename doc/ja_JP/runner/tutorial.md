# `runner` チュートリアル

一般的な single-step benchmark は immutable description として構築し、
measurement effect の前に compile します。

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

stateful または multi-step case では fixture、implementation、oracle、sink
の明示的な combinator を使います。summary の前に raw observation を保存します。

JS と native は別 run とし、elapsed value を同じ母集団として比較しません。
