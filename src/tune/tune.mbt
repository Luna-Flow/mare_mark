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
fn valid_score(score : CandidateScore) -> Bool {
  score.valid &&
  !score.primary.is_nan() &&
  !score.primary.is_inf() &&
  score.primary >= 0.0 &&
  !score.secondary.is_nan() &&
  !score.secondary.is_inf() &&
  score.secondary >= 0.0
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
      let accepted = valid_score(candidate_score)
      if accepted && (best_id == "" || candidate_score.primary < best_primary) {
        best_id = candidate_score.candidate_id
        best_primary = candidate_score.primary
      }
      events.push({
        candidate_id: id,
        kernel_id: id,
        accepted,
        reason: if accepted {
          ""
        } else {
          "measurement"
        },
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
  let frontier = scores.filter(candidate => {
    valid_score(candidate) &&
    scores.all(other => {
      other.candidate_id == candidate.candidate_id ||
      !(valid_score(other) &&
      other.primary <= candidate.primary &&
      other.secondary <= candidate.secondary &&
      (
        other.primary < candidate.primary ||
        other.secondary < candidate.secondary
      ))
    })
  })
  frontier.sort_by((left, right) => {
    if left.primary == right.primary {
      if left.secondary == right.secondary {
        left.candidate_id.compare(right.candidate_id)
      } else {
        left.secondary.compare(right.secondary)
      }
    } else {
      left.primary.compare(right.primary)
    }
  })
  frontier
}

/// Median-based score aggregation. Non-finite and negative measurements are
/// excluded; a candidate with no usable samples cannot win selection.

///|
pub fn score_samples(
  candidate_id : String,
  samples : Array[Double],
  secondary : Double,
) -> CandidateScore {
  let valid_samples = samples.filter(sample => {
    !sample.is_nan() && !sample.is_inf() && sample >= 0.0
  })
  if valid_samples.is_empty() ||
    secondary.is_nan() ||
    secondary.is_inf() ||
    secondary < 0.0 {
    CandidateScore::new(candidate_id, 0.0, secondary, false)
  } else {
    let sorted = valid_samples.copy()
    sorted.sort()
    let middle = sorted.length() / 2
    let median = if sorted.length() % 2 == 0 {
      (sorted[middle - 1] + sorted[middle]) / 2.0
    } else {
      sorted[middle]
    }
    CandidateScore::new(candidate_id, median, secondary, true)
  }
}

/// Selects the fastest valid candidate, breaking practical ties with the
/// secondary metric and then candidate id for deterministic output.

///|
pub fn select_best(
  scores : Array[CandidateScore],
  practical_delta_pct : Double,
  minimize_secondary : Bool,
) -> CandidateScore? {
  let threshold = if practical_delta_pct.is_nan() ||
    practical_delta_pct.is_inf() {
    0.0
  } else {
    practical_delta_pct.max(0.0)
  }
  let valid = scores.filter(valid_score)
  if valid.is_empty() {
    None
  } else {
    let mut fastest = valid[0].primary
    for score in valid {
      if score.primary < fastest {
        fastest = score.primary
      }
    }
    let finalists = valid.filter(score => {
      if fastest == 0.0 {
        score.primary == 0.0
      } else {
        (score.primary - fastest) / fastest * 100.0 <= threshold
      }
    })
    let mut best = finalists[0]
    for index = 1; index < finalists.length(); index = index + 1 {
      let score = finalists[index]
      let better_secondary = if minimize_secondary {
        score.secondary < best.secondary
      } else {
        score.secondary > best.secondary
      }
      if better_secondary ||
        (
          score.secondary == best.secondary &&
          score.candidate_id < best.candidate_id
        ) {
        best = score
      }
    }
    Some(best)
  }
}

/// Deterministic seeded candidate order used by bounded exploration.

///|
pub fn[Candidate] seeded_order(
  candidates : Array[Candidate],
  seed : UInt64,
  candidate_id : (Candidate) -> String,
) -> Array[Candidate] {
  let keyed = candidates.map(candidate => {
    let id = candidate_id(candidate)
    let hash = for
      character in id.to_array()
      hash = seed ^ 1469598103934665603UL {
      continue (hash ^ character.to_int().to_uint64()) * 1099511628211UL
    } nobreak {
      hash
    }
    (hash, candidate)
  })
  keyed.sort_by((left, right) => {
    if left.0 == right.0 {
      candidate_id(left.1).compare(candidate_id(right.1))
    } else if left.0 < right.0 {
      -1
    } else {
      1
    }
  })
  keyed.map(item => item.1)
}

/// Exponential backoff for repeated noisy measurements. The returned sample
/// count is clamped to the configured budget.

///|
pub fn confirmation_count(
  base : Int,
  uncertainty : Double,
  budget : Int,
) -> Int {
  let multiplier = if uncertainty > 0.2 {
    3
  } else if uncertainty > 0.05 {
    2
  } else {
    1
  }
  (base * multiplier).min(budget).max(0)
}
