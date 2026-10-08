# tune_gemm tutorial

This tutorial tunes the blocking parameters of a matrix multiplication end to
end: generate reproducible inputs, filter candidates by constraints, validate
each one against the reference, measure the survivors with `runner`, score and
select them with `tune`, and serialize the result.

## Quick start

```sh
moon add Luna-Flow/mare_mark@0.3.0
```

```text
import {
  "Luna-Flow/mare_mark/tune_gemm",
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/runner",
  "Luna-Flow/mare_mark/tune",
  "moonbitlang/async",
}
```

```moonbit
test "multiply and check" {
  let shape = @tune_gemm.GemmScale::new(
    8, 8, 8, 1, 1, @tune_gemm.row_major(), @tune_gemm.row_major(), @tune_gemm.row_major(),
  )
  let a = @tune_gemm.reproducible_matrix(1UL, 8, 8, @tune_gemm.row_major())
  let b = @tune_gemm.reproducible_matrix(2UL, 8, 8, @tune_gemm.row_major())
  let candidate = @tune_gemm.GemmCandidate::new(
    4, 4, 4, 2, 2, @tune_gemm.pack_ab(), "m_n_k", "scalar",
    @tune_gemm.reusable_workspace(), @tune_gemm.compute_only(),
  )
  let c = @tune_gemm.execute_candidate(shape, a, b, candidate, 4096UL).unwrap()
  inspect(c.length(), content="64")
  inspect(c == @tune_gemm.gemm_reference(shape, a, b), content="true")
}
```

## Everyday tasks

### Filter the candidate grid

```moonbit
test "candidates that fit 64 KiB" {
  let all = @tune_gemm.enumerate_gemm_candidates()
  let fitting = all.filter(c => @tune_gemm.valid_candidate(c, 65536UL))
  inspect(all.length(), content="486")
  inspect(fitting.length(), content="189")
}
```

### Validate every candidate, including tails

```moonbit
test "validate on boundary shapes" {
  let base = @tune_gemm.GemmScale::new(
    16, 12, 9, 1, 1, @tune_gemm.row_major(), @tune_gemm.column_major(), @tune_gemm.row_major(),
  )
  let candidates = @tune_gemm.enumerate_gemm_candidates().filter(c => c.mc == 32 && c.nc == 32 && c.kc == 32)
  let all_correct = @tune_gemm.boundary_shapes(base).all(shape => {
    let a = @tune_gemm.reproducible_matrix(11UL, shape.m, shape.k, shape.layout_a)
    let b = @tune_gemm.reproducible_matrix(12UL, shape.k, shape.n, shape.layout_b)
    candidates.all(c => @tune_gemm.gemm_is_correct(shape, a, b, c, 0.0, 262144UL))
  })
  inspect(candidates.length(), content="27")
  inspect(all_correct, content="true")
}
```

Tolerance `0.0` is correct for the built-in kernel because it sums in the same
order as the reference; the [design page](../design/tune_gemm.md) derives the
tolerance for kernels that reorder.

### Measure and select

Wrap each candidate in a runner implementation, measure them in one case so
they share blocks, and select on the confirmatory medians:

```moonbit
async test "tune two candidates" {
  let shape = @tune_gemm.GemmScale::new(
    24, 24, 24, 1, 1, @tune_gemm.row_major(), @tune_gemm.row_major(), @tune_gemm.row_major(),
  )
  let a = @tune_gemm.reproducible_matrix(1UL, 24, 24, @tune_gemm.row_major())
  let b = @tune_gemm.reproducible_matrix(2UL, 24, 24, @tune_gemm.row_major())
  let candidates = [
    @tune_gemm.GemmCandidate::new(8, 8, 8, 2, 2, @tune_gemm.pack_ab(), "m_n_k", "scalar", @tune_gemm.reusable_workspace(), @tune_gemm.compute_only()),
    @tune_gemm.GemmCandidate::new(32, 32, 32, 4, 4, @tune_gemm.pack_ab(), "m_n_k", "scalar", @tune_gemm.reusable_workspace(), @tune_gemm.compute_only()),
  ]
  let implementations = candidates.map(candidate => {
    @runner.Implementation::stateless(@tune_gemm.candidate_id(candidate), "1", (problem : @tune_gemm.GemmProblem) => {
      @model.OperationResult::completed(@tune_gemm.gemm_blocked(problem.scale, problem.a, problem.b, candidate), ())
    })
  })
  let plan = @runner.single_step("gemm-24", [shape])
    .with_immutable_input(context => @tune_gemm.GemmProblem::from_inputs(context.dataset_key.scale, a, b), _ => "gemm-24")
    .compare(implementations)
    .against_equal(problem => @tune_gemm.gemm_reference(problem.scale, problem.a, problem.b), (expected, actual) => {
      @tune_gemm.validate_gemm(expected, actual, 0.0).valid
    })
    .compile()
    .unwrap()
  let memory = @event.InMemorySink::new()
  let environment = @model.EnvironmentSnapshot::new(
    @model.SemanticEnvironment::new(@model.ExecutionTarget::Native, "moonc", "", "f64"),
    @model.PerformanceEnvironment::new("native", "cpu", "default", 1, "monotonic"),
    @model.ProvenanceEnvironment::new("os", "host", "now", "HEAD", "gemm-tuning"),
  )
  let summary = @runner.run(
    plan,
    @runner.RunContext::new(environment, memory.as_sink(), 3UL, @runner.ProtocolPreset::QuickCheck.validated()),
  )
  inspect(summary.passed_count, content="2")
  let scores = candidates.map(candidate => {
    let id = @tune_gemm.candidate_id(candidate)
    let samples = memory.observations
      .filter(o => o.implementation_id == id && o.valid && o.phase is Confirmatory)
      .map(o => o.raw_elapsed_us)
    @tune.score_samples(id, samples, @tune_gemm.workspace_bytes(candidate).to_double())
  })
  let best = @tune.select_best(scores, 2.0, true)
  inspect(best is Some(_), content="true")
}
```

Which candidate wins depends on your machine; the procedure does not.

### Record the configuration

```moonbit
test "serialize the tuning input" {
  let shapes = [
    @tune_gemm.GemmScale::new(256, 256, 256, 1, 1, @tune_gemm.row_major(), @tune_gemm.row_major(), @tune_gemm.row_major()),
  ]
  let config = @tune_gemm.GemmTuningConfig::new(
    2026UL, shapes, @tune_gemm.enumerate_gemm_candidates(), 262144UL, 3, 20,
  )
  let json = @tune_gemm.config_json(config)
  inspect(json.contains("\"id\":\"32x32x32:2x2:scalar:m_n_k:ab:workspace:compute\""), content="true")
}
```

Store the JSON, the JSONL of the measurements and a `GemmEnvironment` together;
reuse the tuned choice only where `environment_compatible` holds.

## Going further

- Convert µs per operation to GFLOP/s with $2mnk/(t \cdot 10^3)$.
- Hold out shapes: select on some, confirm on `boundary_shapes` and on larger
  shapes; see the [tune tutorial](tune.md).
- Use `seeded_order` to measure a random subset of the 486 candidates when the
  full grid is too slow.

## Common pitfalls

- **Comparing different timing scopes.** The scope is part of the id for a
  reason.
- **Forgetting tails.** A kernel that is right for 64 × 64 can be wrong for
  63 × 64.
- **Equality checks for reordering kernels.** Use the $2\gamma_k k$ bound.
- **Batched operands from one call of `reproducible_matrix`.** It makes one
  matrix; concatenate per batch.

## Next steps

- [tune_gemm API](../api/tune_gemm.md), [tune_gemm design](../design/tune_gemm.md).
- [tune tutorial](tune.md), [runner tutorial](runner.md).
