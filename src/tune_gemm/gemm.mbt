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
  candidate.loop_order
}

///|
pub fn workspace_bytes(candidate : GemmCandidate) -> UInt64 {
  (candidate.mc * candidate.kc +
  candidate.kc * candidate.nc +
  candidate.mc * candidate.nc).to_uint64() *
  4
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
  workspace_bytes(candidate) <= max_workspace_bytes
}

///|
pub struct GemmTuningConfig {
  schema_version : String
  seed : UInt64
  shapes : Array[GemmScale]
  candidates : Array[GemmCandidate]
  max_workspace_bytes : UInt64
  exploration_samples : Int
  confirmation_samples : Int
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
    schema_version: "1.0",
    seed,
    shapes,
    candidates,
    max_workspace_bytes,
    exploration_samples,
    confirmation_samples,
  }
}

///|
pub fn config_json(config : GemmTuningConfig) -> String {
  let shapes = config.shapes.map(shape => {
    "[" +
    shape.m.to_string() +
    "," +
    shape.n.to_string() +
    "," +
    shape.k.to_string() +
    "]"
  })
  let candidates = config.candidates.map(candidate => {
    "\"" + candidate_id(candidate) + "\""
  })
  "{\"schema_version\":\"" +
  config.schema_version +
  "\",\"seed\":\"" +
  config.seed.to_string() +
  "\",\"shapes\":[" +
  shapes.join(",") +
  "],\"candidates\":[" +
  candidates.join(",") +
  "]}"
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
