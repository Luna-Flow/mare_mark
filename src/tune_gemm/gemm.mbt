///|
pub(all) enum Layout {
  RowMajor
  ColumnMajor
}

///|
pub(all) enum AllocationMode {
  FreshPerOperation
  ReuseOutput
  ReusableWorkspace
  PrepackedA
  PrepackedB
  PrepackedAB
}

///|
pub(all) enum TimingScope {
  ComputeOnly
  EndToEnd
  Amortized(Int)
  SteadyState
}

///|
pub(all) enum Packing {
  None
  A
  B
  AB
}

///|
pub fn row_major() -> Layout {
  RowMajor
}

///|
pub fn column_major() -> Layout {
  ColumnMajor
}

///|
pub fn pack_ab() -> Packing {
  AB
}

///|
pub fn reusable_workspace() -> AllocationMode {
  ReusableWorkspace
}

///|
pub fn compute_only() -> TimingScope {
  ComputeOnly
}

///|
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

///|
pub fn GemmScale::new(
  m : Int,
  n : Int,
  k : Int,
  batch : Int,
  reuse_count : Int,
  layout_a : Layout,
  layout_b : Layout,
  layout_c : Layout,
) -> GemmScale {
  { m, n, k, batch, reuse_count, layout_a, layout_b, layout_c }
}

///|
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

///|
pub fn GemmCandidate::new(
  mc : Int,
  nc : Int,
  kc : Int,
  mr : Int,
  nr : Int,
  packing : Packing,
  loop_order : String,
  microkernel_id : String,
  allocation_mode : AllocationMode,
  timing_scope : TimingScope,
) -> GemmCandidate {
  {
    mc,
    nc,
    kc,
    mr,
    nr,
    packing,
    loop_order,
    microkernel_id,
    allocation_mode,
    timing_scope,
  }
}

///|
pub fn candidate_id(candidate : GemmCandidate) -> String {
  candidate.mc.to_string() +
  "x" +
  candidate.nc.to_string() +
  "x" +
  candidate.kc.to_string() +
  ":" +
  candidate.mr.to_string() +
  "x" +
  candidate.nr.to_string() +
  ":" +
  candidate.microkernel_id +
  ":" +
  candidate.loop_order +
  ":" +
  packing_name(candidate.packing) +
  ":" +
  allocation_name(candidate.allocation_mode) +
  ":" +
  timing_name(candidate.timing_scope)
}

///|
fn packing_name(value : Packing) -> String {
  match value {
    None => "none"
    A => "a"
    B => "b"
    AB => "ab"
  }
}

///|
fn allocation_name(value : AllocationMode) -> String {
  match value {
    FreshPerOperation => "fresh"
    ReuseOutput => "reuse_output"
    ReusableWorkspace => "workspace"
    PrepackedA => "prepacked_a"
    PrepackedB => "prepacked_b"
    PrepackedAB => "prepacked_ab"
  }
}

///|
fn timing_name(value : TimingScope) -> String {
  match value {
    ComputeOnly => "compute"
    EndToEnd => "end_to_end"
    Amortized(reuse) => "amortized_" + reuse.to_string()
    SteadyState => "steady_state"
  }
}

///|
fn layout_name(value : Layout) -> String {
  match value {
    RowMajor => "row_major"
    ColumnMajor => "column_major"
  }
}

///|
pub fn workspace_bytes(candidate : GemmCandidate) -> UInt64 {
  if candidate.mc <= 0 || candidate.nc <= 0 || candidate.kc <= 0 {
    0UL
  } else {
    (
      candidate.mc.to_uint64() * candidate.kc.to_uint64() +
      candidate.kc.to_uint64() * candidate.nc.to_uint64() +
      candidate.mc.to_uint64() * candidate.nc.to_uint64()
    ) *
    8UL
  }
}

///|
pub fn valid_candidate(
  candidate : GemmCandidate,
  max_workspace_bytes : UInt64,
) -> Bool {
  candidate.mc > 0 &&
  candidate.nc > 0 &&
  candidate.kc > 0 &&
  candidate.mr > 0 &&
  candidate.nr > 0 &&
  candidate.mr <= candidate.mc &&
  candidate.nr <= candidate.nc &&
  candidate.loop_order == "m_n_k" &&
  (
    candidate.microkernel_id == "scalar" ||
    candidate.microkernel_id == "scalar_f64" ||
    candidate.microkernel_id == "auto"
  ) &&
  (match candidate.timing_scope {
    Amortized(reuse) => reuse > 0
    _ => true
  }) &&
  (match (candidate.packing, candidate.allocation_mode) {
    (None, PrepackedA) => false
    (None, PrepackedB) => false
    (None, PrepackedAB) => false
    (A, PrepackedB) => false
    (B, PrepackedA) => false
    (A, PrepackedAB) => false
    (B, PrepackedAB) => false
    (AB, _) => true
    (_, _) => true
  }) &&
  workspace_bytes(candidate) <= max_workspace_bytes
}

///|
pub fn candidate_valid_for_shape(
  candidate : GemmCandidate,
  shape : GemmScale,
  max_workspace_bytes : UInt64,
) -> Bool {
  valid_candidate(candidate, max_workspace_bytes) &&
  shape.m > 0 &&
  shape.n > 0 &&
  shape.k > 0 &&
  shape.batch > 0 &&
  shape.reuse_count > 0
}

///|
pub fn supported_microkernels() -> Array[String] {
  ["scalar", "scalar_f64", "auto"]
}

///|
pub struct GemmTuningConfig {
  schema_version : TuningSchemaVersion
  seed : UInt64
  shapes : Array[GemmScale]
  candidates : Array[GemmCandidate]
  max_workspace_bytes : UInt64
  exploration_samples : Int
  confirmation_samples : Int
}

/// Metadata attached to tuning runs so results are not silently reused across
/// incompatible compiler, runtime, or CPU environments.

///|
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

///|
pub fn GemmEnvironment::new(
  target : String,
  toolchain : String,
  compiler_flags : String,
  dtype_abi : String,
  runtime : String,
  cpu : String,
  gc : String,
  concurrency : Int,
  clock : String,
) -> GemmEnvironment {
  {
    target,
    toolchain,
    compiler_flags,
    dtype_abi,
    runtime,
    cpu,
    gc,
    concurrency,
    clock,
  }
}

/// Compares all performance-relevant fields while intentionally ignoring
/// provenance (hostname, timestamp, revision, and run id).

///|
pub fn environment_compatible(a : GemmEnvironment, b : GemmEnvironment) -> Bool {
  a.target == b.target &&
  a.toolchain == b.toolchain &&
  a.compiler_flags == b.compiler_flags &&
  a.dtype_abi == b.dtype_abi &&
  a.runtime == b.runtime &&
  a.cpu == b.cpu &&
  a.gc == b.gc &&
  a.concurrency == b.concurrency &&
  a.clock == b.clock
}

/// Deterministic candidate enumeration for blocked scalar GEMM.

///|
pub fn enumerate_gemm_candidates() -> Array[GemmCandidate] {
  let candidates : Array[GemmCandidate] = []
  let blocks = [32, 64, 128]
  let micro = ["scalar", "scalar_f64", "auto"]
  for mc in blocks {
    for nc in blocks {
      for kc in [32, 64] {
        for mr in [2, 4, 8] {
          for nr in [2, 4, 8] {
            for microkernel_id in micro {
              candidates.push(
                GemmCandidate::new(
                  mc,
                  nc,
                  kc,
                  mr,
                  nr,
                  AB,
                  "m_n_k",
                  microkernel_id,
                  ReusableWorkspace,
                  ComputeOnly,
                ),
              )
            }
          }
        }
      }
    }
  }
  candidates
}

///|
pub fn GemmTuningConfig::new(
  seed : UInt64,
  shapes : Array[GemmScale],
  candidates : Array[GemmCandidate],
  max_workspace_bytes : UInt64,
  exploration_samples : Int,
  confirmation_samples : Int,
) -> GemmTuningConfig {
  {
    schema_version: TuningSchemaVersion::V1,
    seed,
    shapes,
    candidates,
    max_workspace_bytes,
    exploration_samples,
    confirmation_samples,
  }
}

/// A logical GEMM input. The arrays use the layouts in `scale`; no implicit
/// transposition is performed when a layout is column major.

///|
pub struct GemmProblem {
  scale : GemmScale
  a : Array[Double]
  b : Array[Double]
  c : Array[Double]
}

///|
pub fn GemmProblem::new(
  scale : GemmScale,
  a : Array[Double],
  b : Array[Double],
  c : Array[Double],
) -> GemmProblem {
  { scale, a, b, c }
}

///|
pub fn GemmProblem::from_inputs(
  scale : GemmScale,
  a : Array[Double],
  b : Array[Double],
) -> GemmProblem {
  {
    scale,
    a,
    b,
    c: Array::makei(scale.batch.max(0) * scale.m.max(0) * scale.n.max(0), _ => {
      0.0
    }),
  }
}

///|
pub fn matrix_length(scale : GemmScale, operand : String) -> Int {
  if scale.m <= 0 || scale.n <= 0 || scale.k <= 0 || scale.batch <= 0 {
    0
  } else if operand == "a" {
    scale.batch * scale.m * scale.k
  } else if operand == "b" {
    scale.batch * scale.k * scale.n
  } else if operand == "c" {
    scale.batch * scale.m * scale.n
  } else {
    0
  }
}

///|
fn at_batch(
  data : Array[Double],
  rows : Int,
  cols : Int,
  layout : Layout,
  batch : Int,
  row : Int,
  col : Int,
) -> Double {
  let offset = batch * rows * cols
  if layout is RowMajor {
    data[offset + row * cols + col]
  } else {
    data[offset + col * rows + row]
  }
}

///|
fn put_batch(
  data : Array[Double],
  rows : Int,
  cols : Int,
  layout : Layout,
  batch : Int,
  row : Int,
  col : Int,
  value : Double,
) -> Unit {
  let offset = batch * rows * cols
  if layout is RowMajor {
    data[offset + row * cols + col] = value
  } else {
    data[offset + col * rows + row] = value
  }
}

/// Reference GEMM used for validation. It supports all row/column layout
/// combinations and returns C in its declared layout.

///|
pub fn gemm_reference(
  scale : GemmScale,
  a : Array[Double],
  b : Array[Double],
) -> Array[Double] {
  if scale.m <= 0 ||
    scale.n <= 0 ||
    scale.k <= 0 ||
    scale.batch <= 0 ||
    a.length() != matrix_length(scale, "a") ||
    b.length() != matrix_length(scale, "b") {
    return []
  }
  let c = Array::makei(scale.batch * scale.m * scale.n, _ => 0.0)
  for batch = 0; batch < scale.batch; batch = batch + 1 {
    for row = 0; row < scale.m; row = row + 1 {
      for col = 0; col < scale.n; col = col + 1 {
        let mut sum = 0.0
        for inner = 0; inner < scale.k; inner = inner + 1 {
          sum += at_batch(
              a,
              scale.m,
              scale.k,
              scale.layout_a,
              batch,
              row,
              inner,
            ) *
            at_batch(b, scale.k, scale.n, scale.layout_b, batch, inner, col)
        }
        put_batch(c, scale.m, scale.n, scale.layout_c, batch, row, col, sum)
      }
    }
  }
  c
}

/// Packs a logical operand into row-major tiles. Packing is explicit so it can
/// be timed separately from compute and reused across repeated measurements.

///|
pub fn pack_operand(
  scale : GemmScale,
  data : Array[Double],
  operand : String,
) -> Array[Double] {
  if scale.m <= 0 ||
    scale.n <= 0 ||
    scale.k <= 0 ||
    scale.batch <= 0 ||
    (operand != "a" && operand != "b") ||
    data.length() != matrix_length(scale, operand) {
    return []
  }
  let rows = if operand == "a" { scale.m } else { scale.k }
  let cols = if operand == "a" { scale.k } else { scale.n }
  let per_batch = rows * cols
  Array::makei(scale.batch * per_batch, index => {
    let batch = index / per_batch
    let within = index % per_batch
    let row = within / cols
    let col = within % cols
    at_batch(
      data,
      rows,
      cols,
      if operand == "a" {
        scale.layout_a
      } else {
        scale.layout_b
      },
      batch,
      row,
      col,
    )
  })
}

/// Blocked scalar microkernel with edge-tile and MR/NR-tail handling.
/// `packing` controls which operands are copied before the blocked loop.

///|
pub fn gemm_blocked(
  scale : GemmScale,
  a : Array[Double],
  b : Array[Double],
  candidate : GemmCandidate,
) -> Array[Double] {
  if scale.m <= 0 ||
    scale.n <= 0 ||
    scale.k <= 0 ||
    scale.batch <= 0 ||
    candidate.mc <= 0 ||
    candidate.nc <= 0 ||
    candidate.kc <= 0 ||
    candidate.mr <= 0 ||
    candidate.nr <= 0 ||
    a.length() != matrix_length(scale, "a") ||
    b.length() != matrix_length(scale, "b") {
    return []
  }
  let packed_a = if candidate.packing is A || candidate.packing is AB {
    Some(pack_operand(scale, a, "a"))
  } else {
    None
  }
  let packed_b = if candidate.packing is B || candidate.packing is AB {
    Some(pack_operand(scale, b, "b"))
  } else {
    None
  }
  let c = Array::makei(scale.batch * scale.m * scale.n, _ => 0.0)
  for batch = 0; batch < scale.batch; batch = batch + 1 {
    let read_a = (row : Int, inner : Int) => {
      match packed_a {
        Some(values) =>
          values[batch * scale.m * scale.k + row * scale.k + inner]
        None => at_batch(a, scale.m, scale.k, scale.layout_a, batch, row, inner)
      }
    }
    let read_b = (inner : Int, col : Int) => {
      match packed_b {
        Some(values) =>
          values[batch * scale.k * scale.n + inner * scale.n + col]
        None => at_batch(b, scale.k, scale.n, scale.layout_b, batch, inner, col)
      }
    }
    let mut tile_m = 0
    while tile_m < scale.m {
      let mut tile_n = 0
      while tile_n < scale.n {
        let mut tile_k = 0
        while tile_k < scale.k {
          let end_m = (tile_m + candidate.mc).min(scale.m)
          let end_n = (tile_n + candidate.nc).min(scale.n)
          let end_k = (tile_k + candidate.kc).min(scale.k)
          let mut row = tile_m
          while row < end_m {
            let row_end = (row + candidate.mr).min(end_m)
            let mut col = tile_n
            while col < end_n {
              let col_end = (col + candidate.nr).min(end_n)
              let mut i = row
              while i < row_end {
                let mut j = col
                while j < col_end {
                  let mut value = if tile_k == 0 {
                    0.0
                  } else {
                    at_batch(c, scale.m, scale.n, scale.layout_c, batch, i, j)
                  }
                  let mut inner = tile_k
                  while inner < end_k {
                    value += read_a(i, inner) * read_b(inner, j)
                    inner = inner + 1
                  }
                  put_batch(
                    c,
                    scale.m,
                    scale.n,
                    scale.layout_c,
                    batch,
                    i,
                    j,
                    value,
                  )
                  j = j + 1
                }
                i = i + 1
              }
              col = col + candidate.nr
            }
            row = row + candidate.mr
          }
          tile_k = tile_k + candidate.kc
        }
        tile_n = tile_n + candidate.nc
      }
      tile_m = tile_m + candidate.mc
    }
  }
  c
}

/// Executes a candidate after rejecting malformed dimensions or constraints.
/// Invalid candidates return `None` rather than producing a misleading result.

///|
pub fn execute_candidate(
  scale : GemmScale,
  a : Array[Double],
  b : Array[Double],
  candidate : GemmCandidate,
  max_workspace_bytes : UInt64,
) -> Array[Double]? {
  if !candidate_valid_for_shape(candidate, scale, max_workspace_bytes) ||
    a.length() != matrix_length(scale, "a") ||
    b.length() != matrix_length(scale, "b") {
    None
  } else {
    Some(gemm_blocked(scale, a, b, candidate))
  }
}

///|
pub struct GemmValidation {
  valid : Bool
  mismatches : Int
  max_abs_error : Double
}

///|
pub fn validate_gemm(
  expected : Array[Double],
  actual : Array[Double],
  tolerance : Double,
) -> GemmValidation {
  let count = expected.length().min(actual.length())
  let mut mismatches = expected.length() - count + actual.length() - count
  let mut max_error = 0.0
  if tolerance.is_nan() || tolerance.is_inf() || tolerance < 0.0 {
    return { valid: false, mismatches: count.max(1), max_abs_error: max_error }
  }
  for index = 0; index < count; index = index + 1 {
    let expected_value = expected[index]
    let actual_value = actual[index]
    if expected_value.is_nan() ||
      expected_value.is_inf() ||
      actual_value.is_nan() ||
      actual_value.is_inf() {
      mismatches = mismatches + 1
    } else {
      let error = (expected_value - actual_value).abs()
      if error > max_error {
        max_error = error
      }
      if error > tolerance {
        mismatches = mismatches + 1
      }
    }
  }
  { valid: mismatches == 0, mismatches, max_abs_error: max_error }
}

///|
pub fn gemm_is_correct(
  scale : GemmScale,
  a : Array[Double],
  b : Array[Double],
  candidate : GemmCandidate,
  tolerance : Double,
  max_workspace_bytes : UInt64,
) -> Bool {
  match execute_candidate(scale, a, b, candidate, max_workspace_bytes) {
    None => false
    Some(actual) =>
      validate_gemm(gemm_reference(scale, a, b), actual, tolerance).valid
  }
}

/// Deterministic input generation keyed by a seed and shape.

///|
pub fn reproducible_matrix(
  seed : UInt64,
  rows : Int,
  cols : Int,
  layout : Layout,
) -> Array[Double] {
  if rows <= 0 || cols <= 0 {
    return []
  }
  let mut state = seed ^ 0x9E3779B97F4A7C15
  let logical = Array::makei(rows * cols, _ => {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let value = (state >> 32).to_double() % 2001.0 / 1000.0 - 1.0
    value
  })
  Array::makei(rows * cols, index => {
    let row = if layout is RowMajor { index / cols } else { index % rows }
    let col = if layout is RowMajor { index % cols } else { index / rows }
    logical[row * cols + col]
  })
}

///|
pub fn config_json(config : GemmTuningConfig) -> String {
  let shapes = config.shapes.map(shape => {
    Json::object({
      "m": Json::number(shape.m.to_double()),
      "n": Json::number(shape.n.to_double()),
      "k": Json::number(shape.k.to_double()),
      "batch": Json::number(shape.batch.to_double()),
      "reuse_count": Json::number(shape.reuse_count.to_double()),
      "layout_a": Json::string(layout_name(shape.layout_a)),
      "layout_b": Json::string(layout_name(shape.layout_b)),
      "layout_c": Json::string(layout_name(shape.layout_c)),
    })
  })
  let candidates = config.candidates.map(candidate => {
    Json::object({
      "id": Json::string(candidate_id(candidate)),
      "mc": Json::number(candidate.mc.to_double()),
      "nc": Json::number(candidate.nc.to_double()),
      "kc": Json::number(candidate.kc.to_double()),
      "mr": Json::number(candidate.mr.to_double()),
      "nr": Json::number(candidate.nr.to_double()),
      "packing": Json::string(packing_name(candidate.packing)),
      "loop_order": Json::string(candidate.loop_order),
      "microkernel": Json::string(candidate.microkernel_id),
      "allocation": Json::string(allocation_name(candidate.allocation_mode)),
      "timing_scope": Json::string(timing_name(candidate.timing_scope)),
    })
  })
  Json::object({
    "schema_version": Json::string(config.schema_version.identifier()),
    "seed": Json::string(config.seed.to_string()),
    "shapes": Json::array(shapes),
    "candidates": Json::array(candidates),
    "max_workspace_bytes": Json::string(config.max_workspace_bytes.to_string()),
    "exploration_samples": Json::number(config.exploration_samples.to_double()),
    "confirmation_samples": Json::number(
      config.confirmation_samples.to_double(),
    ),
  }).stringify()
}

///|
pub fn boundary_shapes(shape : GemmScale) -> Array[GemmScale] {
  [
    GemmScale::new(
      shape.m.max(1) - 1,
      shape.n,
      shape.k,
      shape.batch,
      shape.reuse_count,
      shape.layout_a,
      shape.layout_b,
      shape.layout_c,
    ),
    shape,
    GemmScale::new(
      shape.m + 1,
      shape.n,
      shape.k,
      shape.batch,
      shape.reuse_count,
      shape.layout_a,
      shape.layout_b,
      shape.layout_c,
    ),
  ]
}
