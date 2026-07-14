///|
pub struct CandidateSpace[Candidate] {
  enumerate : () -> Array[Candidate]
  candidate_id : (Candidate) -> String
  valid : (Candidate) -> Bool
  neighbors : (Candidate) -> Array[Candidate]
}

///|
pub fn[Candidate] CandidateSpace::new(
  enumerate : () -> Array[Candidate],
  candidate_id : (Candidate) -> String,
  valid : (Candidate) -> Bool,
  neighbors : (Candidate) -> Array[Candidate],
) -> CandidateSpace[Candidate] {
  { enumerate, candidate_id, valid, neighbors }
}

///|
pub struct BuiltCandidate[Prepared, Output, Context] {
  candidate_id : String
  implementation : @runner.Implementation[Prepared, Output, Context]
  kernel_id : String
}

///|
pub fn[Prepared, Output, Context] BuiltCandidate::new(
  candidate_id : String,
  implementation : @runner.Implementation[Prepared, Output, Context],
  kernel_id : String,
) -> BuiltCandidate[Prepared, Output, Context] {
  { candidate_id, implementation, kernel_id }
}

///|
pub(all) enum HoldoutPlan[Scale] {
  MeasurementHoldout(Int)
  DatasetHoldout(Array[Int])
  ShapeHoldout(Array[Scale])
  WorkloadHoldout(String)
  Combined(Array[HoldoutPlan[Scale]])
}

///|
pub struct TuningBudget[Scale] {
  max_candidates : Int
  max_measurements : Int
  max_elapsed_us : Double?
  exploration_samples : Int
  confirmation_samples : Int
  finalists : Int
  holdout : HoldoutPlan[Scale]
}

///|
pub fn[Scale] TuningBudget::new(
  max_candidates : Int,
  max_measurements : Int,
  max_elapsed_us : Double?,
  exploration_samples : Int,
  confirmation_samples : Int,
  finalists : Int,
  holdout : HoldoutPlan[Scale],
) -> TuningBudget[Scale] {
  {
    max_candidates,
    max_measurements,
    max_elapsed_us,
    exploration_samples,
    confirmation_samples,
    finalists,
    holdout,
  }
}

///|
pub struct TuningObjective {
  practical_delta_pct : Double
  max_workspace_bytes : UInt64?
  minimize_secondary : Bool
}

///|
pub fn TuningObjective::new(
  practical_delta_pct : Double,
  max_workspace_bytes : UInt64?,
  minimize_secondary : Bool,
) -> TuningObjective {
  { practical_delta_pct, max_workspace_bytes, minimize_secondary }
}

///|
pub struct CandidateScore {
  candidate_id : String
  primary : Double
  secondary : Double
  valid : Bool
}

///|
pub fn CandidateScore::new(
  candidate_id : String,
  primary : Double,
  secondary : Double,
  valid : Bool,
) -> CandidateScore {
  { candidate_id, primary, secondary, valid }
}

///|
pub struct BuildEvent {
  candidate_id : String
  kernel_id : String
  accepted : Bool
  reason : String
}

///|
pub struct TuningResult {
  scores : Array[CandidateScore]
  build_events : Array[BuildEvent]
  policy : String
}

///|
pub fn[Candidate] exhaustive_scores(
  space : CandidateSpace[Candidate],
  budget : Int,
  score : (Candidate) -> CandidateScore,
) -> TuningResult {
  let candidates = (space.enumerate)()
  let limit = budget.min(candidates.length()).max(0)
  let scores = []
  let events = []
  let mut best_id = ""
  let mut best_primary = 0.0
  for index = 0; index < limit; index = index + 1 {
    let candidate = candidates[index]
    let id = (space.candidate_id)(candidate)
    if (space.valid)(candidate) {
      let candidate_score = score(candidate)
      scores.push(candidate_score)
      if best_id == "" || candidate_score.primary < best_primary {
        best_id = candidate_score.candidate_id
        best_primary = candidate_score.primary
      }
      events.push({
        candidate_id: id,
        kernel_id: id,
        accepted: true,
        reason: "",
      })
    } else {
      events.push({
        candidate_id: id,
        kernel_id: id,
        accepted: false,
        reason: "constraint",
      })
    }
  }
  { scores, build_events: events, policy: "global:" + best_id }
}

///|
pub fn pareto_frontier(scores : Array[CandidateScore]) -> Array[CandidateScore] {
  scores.filter(candidate => {
    scores.all(other => {
      other.candidate_id == candidate.candidate_id ||
      other.primary > candidate.primary ||
      other.secondary >= candidate.secondary
    })
  })
}
