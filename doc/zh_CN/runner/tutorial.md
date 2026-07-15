# `runner` 教程

常见单步 benchmark 使用不可变描述，并在产生任何测量 effect 前编译：

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

有状态或多步 case 使用显式 fixture、implementation、oracle 与 sink 组合器。
先保留原始 observation，再计算 summary。

JS 与 native 必须使用独立 run；两者的 elapsed 值不是同一可比较总体。
