///|
pub struct ReferenceOracle[Input, Expected, Output, Context] {
  id : String
  initial_context : () -> Context
  sequence_length : (Input) -> Int
  compute_expected : (Input, Int, Context) -> @model.OperationResult[
    Expected,
    Context,
  ]
  validate : (
    Input,
    Int,
    @model.ExecutionOutcome[Expected],
    @model.ExecutionOutcome[Output],
  ) -> @model.ValidationStatus
  expected_text : (Expected) -> String
}

///|
pub fn[Input, Expected, Output, Context] ReferenceOracle::new(
  id : String,
  initial_context : () -> Context,
  sequence_length : (Input) -> Int,
  compute_expected : (Input, Int, Context) -> @model.OperationResult[
    Expected,
    Context,
  ],
  validate : (
    Input,
    Int,
    @model.ExecutionOutcome[Expected],
    @model.ExecutionOutcome[Output],
  ) -> @model.ValidationStatus,
  expected_text : (Expected) -> String,
) -> ReferenceOracle[Input, Expected, Output, Context] {
  {
    id,
    initial_context,
    sequence_length,
    compute_expected,
    validate,
    expected_text,
  }
}

///|
pub struct RelationalOracle[Input, Output] {
  id : String
  validate_pair : (
    Input,
    Int,
    String,
    @model.ExecutionOutcome[Output],
    String,
    @model.ExecutionOutcome[Output],
  ) -> @model.ValidationStatus
}

///|
pub fn[Input, Output] RelationalOracle::new(
  id : String,
  validate_pair : (
    Input,
    Int,
    String,
    @model.ExecutionOutcome[Output],
    String,
    @model.ExecutionOutcome[Output],
  ) -> @model.ValidationStatus,
) -> RelationalOracle[Input, Output] {
  { id, validate_pair }
}

///|
pub(all) enum OracleSpec[Input, Expected, Output, Context] {
  Reference(ReferenceOracle[Input, Expected, Output, Context])
  Relational(RelationalOracle[Input, Output])
  ReferenceAndRelational(
    ReferenceOracle[Input, Expected, Output, Context],
    RelationalOracle[Input, Output]
  )
}

///|
pub fn[Input, Expected, Output, Context] validate_reference(
  oracle : ReferenceOracle[Input, Expected, Output, Context],
  input : Input,
  step_id : Int,
  expected : @model.ExecutionOutcome[Expected],
  actual : @model.ExecutionOutcome[Output],
  implementation_id : String,
  scale_text : String,
) -> @model.Validation {
  @model.Validation::new(
    (oracle.validate)(input, step_id, expected, actual),
    oracle.id,
    implementation_id,
    scale_text,
  )
}

///|
pub struct Shrinker[Input] {
  candidates : (Input) -> Array[Input]
  text : (Input) -> String
  max_steps : Int
}

///|
pub fn[Input] Shrinker::new(
  candidates : (Input) -> Array[Input],
  text : (Input) -> String,
  max_steps? : Int = 128,
) -> Shrinker[Input] {
  { candidates, text, max_steps }
}

///|
pub fn[Input] shrink(
  initial : Input,
  shrinker : Shrinker[Input],
  still_fails : (Input) -> Bool,
) -> (Input, Array[String]) {
  let mut current = initial
  let path = []
  let mut steps = 0
  while steps < shrinker.max_steps {
    let mut reduced = false
    for candidate in (shrinker.candidates)(current) {
      steps += 1
      if still_fails(candidate) {
        current = candidate
        path.push((shrinker.text)(candidate))
        reduced = true
        break
      }
      if steps >= shrinker.max_steps {
        break
      }
    }
    if !reduced {
      break
    }
  }
  (current, path)
}

///|
pub struct ScaleDomain[Scale] {
  values : Array[Scale]
  compare : (Scale, Scale) -> Int
  text : (Scale) -> String
}

///|
pub fn[Scale] ScaleDomain::new(
  values : Array[Scale],
  compare : (Scale, Scale) -> Int,
  text : (Scale) -> String,
) -> ScaleDomain[Scale] {
  { values, compare, text }
}

///|
pub fn[Scale] crossover_from_labels(
  domain : ScaleDomain[Scale],
  labels : Array[String],
) -> @model.CrossoverResult[Scale] {
  let evidence = labels.copy()
  if domain.values.length() != labels.length() || labels.is_empty() {
    @model.CrossoverResult::inconclusive(
      "label/domain length mismatch", evidence,
    )
  } else {
    let mut transitions = 0
    let mut transition_index = -1
    for index = 1; index < labels.length(); index = index + 1 {
      if labels[index] != labels[index - 1] &&
        labels[index] != "Unknown" &&
        labels[index - 1] != "Unknown" {
        transitions += 1
        transition_index = index
      }
    }
    if transitions == 0 {
      @model.CrossoverResult::no_crossover(
        "no stable label transition", evidence,
      )
    } else if transitions > 1 {
      @model.CrossoverResult::non_monotonic(evidence)
    } else {
      let below = domain.values[transition_index - 1]
      let at_or_above = domain.values[transition_index]
      @model.CrossoverResult::found(
        @model.ScaleBoundary::new(below, at_or_above),
        "piecewise-confirmed",
        evidence,
      )
    }
  }
}

///|
pub fn comparator_label(
  relative_delta_pct : Double,
  practical_delta_pct : Double,
) -> String {
  if relative_delta_pct <= -practical_delta_pct {
    "A"
  } else if relative_delta_pct >= practical_delta_pct {
    "B"
  } else {
    "Unknown"
  }
}
