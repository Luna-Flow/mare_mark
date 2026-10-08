# tune_gemm API

`Luna-Flow/mare_mark/tune_gemm` is a worked tuning domain: double-precision
batched matrix multiplication $C = AB$ with configurable layouts, a blocked
scalar implementation parameterized by cache and register block sizes, a
reference implementation for validation, a deterministic candidate grid,
workspace accounting, reproducible input matrices and a serializable tuning
configuration. See the [tune_gemm design](../design/tune_gemm.md).

Source: [`src/tune_gemm/gemm.mbt`](../../../src/tune_gemm/gemm.mbt),
[`src/tune_gemm/versioning.mbt`](../../../src/tune_gemm/versioning.mbt).

```text
import {
  "Luna-Flow/mare_mark/tune_gemm",
}
```

## Problem description

### `GemmScale`

`GemmScale` describes one problem shape.

```mbti
pub struct GemmScale {
  m : Int
  n : Int
  k : Int
  batch : Int
  reuse_count : Int
  layout_a : Layout
  layout_b : Layout
  layout_c : Layout
}
pub fn GemmScale::new(Int, Int, Int, Int, Int, Layout, Layout, Layout) -> Self
```

$A$ is $m \times k$, $B$ is $k \times n$, $C$ is $m \times n$, and `batch`
independent products are stored one after another. `reuse_count` records how
often the operands are reused (for amortized timing scopes); the kernels do
not read it.

### `Layout`, `row_major`, `column_major`

`Layout` is the storage order of one matrix.

```mbti
pub(all) enum Layout {
  RowMajor
  ColumnMajor
}
pub fn row_major() -> Layout
pub fn column_major() -> Layout
```

Element $(i, j)$ of batch $b$ of an $r \times c$ matrix is at
$b\,rc + i\,c + j$ (row major) or $b\,rc + j\,r + i$ (column major).

### `matrix_length`

`matrix_length` returns the number of elements of operand `"a"`, `"b"` or
`"c"`.

```mbti
pub fn matrix_length(GemmScale, String) -> Int
```

It is `batch * m * k`, `batch * k * n` or `batch * m * n`, and `0` for an
unknown operand or a non-positive dimension or batch.

### `GemmProblem`

`GemmProblem` bundles a shape with its operands.

```mbti
pub struct GemmProblem {
  scale : GemmScale
  a : Array[Double]
  b : Array[Double]
  c : Array[Double]
}
pub fn GemmProblem::new(GemmScale, Array[Double], Array[Double], Array[Double]) -> Self
pub fn GemmProblem::from_inputs(GemmScale, Array[Double], Array[Double]) -> Self
```

`from_inputs` allocates a zero `c` of `batch * m * n` elements. Arrays are used
as given; no transposition is performed.

### `boundary_shapes`

`boundary_shapes` returns the shape with $m - 1$, the shape itself and the
shape with $m + 1$.

```mbti
pub fn boundary_shapes(GemmScale) -> Array[GemmScale]
```

Shapes just around a block size exercise the tail handling of a kernel. For
$m = 0$ the first shape also has $m = 0$.

## Candidates

### `GemmCandidate`

`GemmCandidate` is one kernel configuration.

```mbti
pub struct GemmCandidate {
  mc : Int
  nc : Int
  kc : Int
  mr : Int
  nr : Int
  packing : Packing
  loop_order : String
  microkernel_id : String
  allocation_mode : AllocationMode
  timing_scope : TimingScope
}
pub fn GemmCandidate::new(Int, Int, Int, Int, Int, Packing, String, String, AllocationMode, TimingScope) -> Self
```

`mc`, `nc`, `kc` are the cache block sizes, `mr`, `nr` the register block
sizes. `loop_order` must be `"m_n_k"` and `microkernel_id` one of
`supported_microkernels()` for the candidate to be valid.

### `Packing`, `pack_ab`

`Packing` says which operands are copied into row-major form before the
blocked loop.

```mbti
pub(all) enum Packing {
  None
  A
  B
  AB
}
pub fn pack_ab() -> Packing
```

### `AllocationMode`, `reusable_workspace`

`AllocationMode` says how buffers are obtained.

```mbti
pub(all) enum AllocationMode {
  FreshPerOperation
  ReuseOutput
  ReusableWorkspace
  PrepackedA
  PrepackedB
  PrepackedAB
}
pub fn reusable_workspace() -> AllocationMode
```

A prepacked mode requires the corresponding packing (see `valid_candidate`).
The built-in kernel allocates fresh buffers in every mode; the field describes
the experiment for the harness and the report.

### `TimingScope`, `compute_only`

`TimingScope` says what a measurement of the candidate includes.

```mbti
pub(all) enum TimingScope {
  ComputeOnly
  EndToEnd
  Amortized(Int)
  SteadyState
}
pub fn compute_only() -> TimingScope
```

Map it to a fixture `SetupPolicy` when measuring: `ComputeOnly` excludes
packing and allocation, `EndToEnd` includes them, `Amortized(r)` spreads setup
over `r` uses, `SteadyState` measures repeated calls on warm buffers.

### `candidate_id`

`candidate_id` returns a stable text id of a candidate.

```mbti
pub fn candidate_id(GemmCandidate) -> String
```

The format is `mc x nc x kc : mr x nr : microkernel : loop_order : packing :
allocation : timing` without spaces.

```moonbit
test "candidate ids" {
  let candidate = @tune_gemm.GemmCandidate::new(
    64, 64, 32, 4, 4, @tune_gemm.pack_ab(), "m_n_k", "scalar",
    @tune_gemm.reusable_workspace(), @tune_gemm.compute_only(),
  )
  inspect(@tune_gemm.candidate_id(candidate), content="64x64x32:4x4:scalar:m_n_k:ab:workspace:compute")
}
```

### `supported_microkernels`

```mbti
pub fn supported_microkernels() -> Array[String]
```

Returns `["scalar", "scalar_f64", "auto"]`. All three run the same scalar
loop; the ids exist so that a harness can name kernel variants.

### `enumerate_gemm_candidates`

`enumerate_gemm_candidates` returns the default candidate grid.

```mbti
pub fn enumerate_gemm_candidates() -> Array[GemmCandidate]
```

The grid is $mc, nc \in \{32, 64, 128\}$, $kc \in \{32, 64\}$,
$mr, nr \in \{2, 4, 8\}$ and the three microkernel ids, with `AB` packing,
`m_n_k` order, `ReusableWorkspace` and `ComputeOnly`: $3 \cdot 3 \cdot 2 \cdot 3 \cdot 3 \cdot 3 = 486$
candidates in a fixed order.

### `workspace_bytes`

`workspace_bytes` returns the packing workspace of a candidate.

```mbti
pub fn workspace_bytes(GemmCandidate) -> UInt64
```

It is $8\,(mc \cdot kc + kc \cdot nc + mc \cdot nc)$ bytes: an $mc \times kc$
block of $A$, a $kc \times nc$ panel of $B$ and an $mc \times nc$ block of $C$
in doubles; `0` when a block size is not positive.

### `valid_candidate`

`valid_candidate` checks a candidate against the kernel's constraints and a
workspace limit.

```mbti
pub fn valid_candidate(GemmCandidate, UInt64) -> Bool
```

All of: positive block sizes; $mr \le mc$ and $nr \le nc$; loop order
`m_n_k`; a supported microkernel id; `Amortized(r)` with $r > 0$; a prepacked
allocation only with matching packing (`PrepackedA` needs `A` or `AB`,
`PrepackedB` needs `B` or `AB`, `PrepackedAB` needs `AB`); and
`workspace_bytes` at most the limit.

### `candidate_valid_for_shape`

```mbti
pub fn candidate_valid_for_shape(GemmCandidate, GemmScale, UInt64) -> Bool
```

`valid_candidate` and positive $m$, $n$, $k$, `batch` and `reuse_count`.

```moonbit
test "constraints" {
  let candidate = @tune_gemm.GemmCandidate::new(
    128, 128, 64, 8, 8, @tune_gemm.pack_ab(), "m_n_k", "auto",
    @tune_gemm.reusable_workspace(), @tune_gemm.compute_only(),
  )
  inspect(@tune_gemm.workspace_bytes(candidate), content="262144")
  inspect(@tune_gemm.valid_candidate(candidate, 262144UL), content="true")
  inspect(@tune_gemm.valid_candidate(candidate, 262143UL), content="false")
  inspect(@tune_gemm.enumerate_gemm_candidates().length(), content="486")
}
```

## Kernels

### `gemm_reference`

`gemm_reference` computes $C = AB$ with the textbook triple loop.

```mbti
pub fn gemm_reference(GemmScale, Array[Double], Array[Double]) -> Array[Double]
```

Each entry is accumulated from $0.0$ in increasing $k$ order and stored in
`layout_c`. Returns `[]` for non-positive dimensions or operands of the wrong
length.

### `gemm_blocked`

`gemm_blocked` computes $C = AB$ with cache and register blocking.

```mbti
pub fn gemm_blocked(GemmScale, Array[Double], Array[Double], GemmCandidate) -> Array[Double]
```

Loops run over $mc \times nc \times kc$ blocks, then $mr \times nr$ register
tiles, with partial tiles at the edges. Operands are packed according to
`packing`. Returns `[]` for invalid dimensions, block sizes or operand
lengths; it does not check the other candidate constraints.

### `pack_operand`

`pack_operand` copies operand `"a"` or `"b"` into row-major order.

```mbti
pub fn pack_operand(GemmScale, Array[Double], String) -> Array[Double]
```

The result has the same length; each batch is stored row by row regardless of
the source layout. Returns `[]` for an unknown operand or invalid input.

### `execute_candidate`

`execute_candidate` runs a candidate after checking it.

```mbti
pub fn execute_candidate(GemmScale, Array[Double], Array[Double], GemmCandidate, UInt64) -> Array[Double]?
```

Returns `None` when `candidate_valid_for_shape` fails or an operand has the
wrong length, otherwise `Some(gemm_blocked(...))`.

## Validation

### `GemmValidation`

```mbti
pub struct GemmValidation {
  valid : Bool
  mismatches : Int
  max_abs_error : Double
}
```

### `validate_gemm`

`validate_gemm` compares two result arrays element-wise with an absolute
tolerance.

```mbti
pub fn validate_gemm(Array[Double], Array[Double], Double) -> GemmValidation
```

Mismatches are: every element past the shorter length, every pair with a
non-finite value, and every pair with $\lvert e - a\rvert$ above the
tolerance. `max_abs_error` is the largest finite difference. A tolerance that
is `NaN`, infinite or negative gives `valid = false`.

### `gemm_is_correct`

`gemm_is_correct` executes a candidate and validates it against
`gemm_reference`.

```mbti
pub fn gemm_is_correct(GemmScale, Array[Double], Array[Double], GemmCandidate, Double, UInt64) -> Bool
```

Arguments: shape, $A$, $B$, candidate, tolerance, workspace limit.

```moonbit
test "blocked equals reference" {
  let shape = @tune_gemm.GemmScale::new(
    5, 7, 3, 1, 1, @tune_gemm.row_major(), @tune_gemm.column_major(), @tune_gemm.row_major(),
  )
  let a = @tune_gemm.reproducible_matrix(1UL, 5, 3, @tune_gemm.row_major())
  let b = @tune_gemm.reproducible_matrix(2UL, 3, 7, @tune_gemm.column_major())
  let candidate = @tune_gemm.GemmCandidate::new(
    4, 4, 2, 2, 2, @tune_gemm.pack_ab(), "m_n_k", "scalar",
    @tune_gemm.reusable_workspace(), @tune_gemm.compute_only(),
  )
  inspect(@tune_gemm.gemm_is_correct(shape, a, b, candidate, 0.0, 4096UL), content="true")
  let check = @tune_gemm.validate_gemm([1.0, 2.0], [1.0, 2.5], 0.1)
  inspect(check.mismatches, content="1")
  inspect(check.max_abs_error, content="0.5")
}
```

## Inputs and configuration

### `reproducible_matrix`

`reproducible_matrix` generates a deterministic matrix with entries in
$[-1, 1]$.

```mbti
pub fn reproducible_matrix(UInt64, Int, Int, Layout) -> Array[Double]
```

Arguments: seed, rows, columns, layout. Entries are multiples of $0.001$
drawn from a 64-bit linear congruential generator and stored in the requested
layout, so the same seed gives the same logical matrix in both layouts.
Returns `[]` for non-positive dimensions. It generates one matrix; concatenate
several for `batch > 1`.

```moonbit
test "the same logical matrix in both layouts" {
  let rows = @tune_gemm.reproducible_matrix(5UL, 2, 3, @tune_gemm.row_major())
  let cols = @tune_gemm.reproducible_matrix(5UL, 2, 3, @tune_gemm.column_major())
  inspect(rows[1 * 3 + 2] == cols[2 * 2 + 1], content="true")
  inspect(rows.all(x => x >= -1.0 && x <= 1.0), content="true")
}
```

### `GemmTuningConfig`

`GemmTuningConfig` is the complete, serializable input of a tuning run.

```mbti
pub struct GemmTuningConfig {
  schema_version : TuningSchemaVersion
  seed : UInt64
  shapes : Array[GemmScale]
  candidates : Array[GemmCandidate]
  max_workspace_bytes : UInt64
  exploration_samples : Int
  confirmation_samples : Int
}
pub fn GemmTuningConfig::new(UInt64, Array[GemmScale], Array[GemmCandidate], UInt64, Int, Int) -> Self
```

`new` sets `schema_version` to `TuningSchemaVersion::V1`.

### `config_json`

`config_json` serializes a tuning configuration.

```mbti
pub fn config_json(GemmTuningConfig) -> String
```

The JSON has `schema_version` (`"mmkts_1"`), `seed` and `max_workspace_bytes`
as decimal strings (64-bit values do not fit a JSON number exactly), `shapes`,
`candidates` (each with its `id`) and the two sample counts.

```moonbit
test "configuration JSON" {
  let shape = @tune_gemm.GemmScale::new(
    64, 64, 64, 1, 1, @tune_gemm.row_major(), @tune_gemm.row_major(), @tune_gemm.row_major(),
  )
  let config = @tune_gemm.GemmTuningConfig::new(42UL, [shape], [], 262144UL, 3, 10)
  let json = @tune_gemm.config_json(config)
  inspect(json.contains("\"schema_version\":\"mmkts_1\""), content="true")
  inspect(json.contains("\"seed\":\"42\""), content="true")
}
```

### `TuningSchemaVersion`

```mbti
pub(all) enum TuningSchemaVersion {
  V1
}
pub fn TuningSchemaVersion::identifier(Self) -> String
pub fn TuningSchemaVersion::implementation(Self) -> String
pub fn TuningSchemaVersion::lifecycle(Self) -> @model.VersionLifecycle
pub fn TuningSchemaVersion::version(Self) -> Int
```

`identifier()` is `"mmkts_1"`; `V1` is `Supported`.

### `GemmEnvironment`, `environment_compatible`

`GemmEnvironment` is a flat environment record for tuning results.

```mbti
pub struct GemmEnvironment {
  target : String
  toolchain : String
  compiler_flags : String
  dtype_abi : String
  runtime : String
  cpu : String
  gc : String
  concurrency : Int
  clock : String
}
pub fn GemmEnvironment::new(String, String, String, String, String, String, String, Int, String) -> Self
pub fn environment_compatible(GemmEnvironment, GemmEnvironment) -> Bool
```

`environment_compatible` is true when all nine fields are equal. A tuned
configuration is only reusable in a compatible environment.
