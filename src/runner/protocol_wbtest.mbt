///|
fn protocol_with(
  design : @model.ExperimentDesign,
  coverage : @model.ValidationCoverage,
  exploratory : Int32,
  confirmatory : Int32,
  warmup~ : Int32 = 1,
  repeats~ : Int32 = 1,
) -> @model.RunProtocol {
  @model.RunProtocol::new(
    design,
    warmup,
    None,
    @model.CalibrationProtocol::new(
      1.0,
      2,
      2,
      10.0,
      @model.BatchPolicy::PerImplementation,
    ),
    1.0,
    @model.OrderPolicy::BalancedBlocks(3),
    @model.OutlierPolicy::ReportOnly,
    coverage,
    exploratory,
    confirmatory,
    repeats_per_dataset=repeats,
  )
}

///|
test "protocol validation checks repeats per dataset" {
  let hierarchical = (exploratory, confirmatory, repeats) => {
    validate_protocol(
      protocol_with(
        @model.ExperimentDesign::HierarchicalDatasetsAndRepeats,
        @model.ValidationCoverage::EveryDataset,
        exploratory,
        confirmatory,
        repeats~,
      ),
    )
  }
  assert_true(hierarchical(4, 6, 2) is Ok(_))
  assert_true(hierarchical(0, 3, 3) is Ok(_))
  assert_true(
    hierarchical(4, 6, 0) is Err([InvalidInteger("repeats_per_dataset", 0)]),
  )
  assert_true(
    hierarchical(3, 5, 2)
    is Err(
      [
        IndivisibleSamples("exploratory_samples", 3, 2),
        IndivisibleSamples("confirmatory_samples", 5, 2),
      ]
    ),
  )
  for
    design in [
      @model.ExperimentDesign::FixedDatasetRepeatedMeasurements,
      @model.ExperimentDesign::MultipleDatasetsSingleMeasurement,
    ] {
    assert_true(
      validate_protocol(
        protocol_with(
          design,
          @model.ValidationCoverage::EveryDataset,
          2,
          2,
          repeats=2,
        ),
      )
      is Err([UnusedRepeatsPerDataset(2)]),
    )
    assert_true(
      validate_protocol(
        protocol_with(design, @model.ValidationCoverage::EveryDataset, 2, 2),
      )
      is Ok(_),
    )
  }
  let gate = ProtocolPreset::RegressionGate.validated().protocol
  assert_true(
    gate.experiment_design
    is @model.ExperimentDesign::HierarchicalDatasetsAndRepeats,
  )
  assert_eq(gate.repeats_per_dataset, 5)
  assert_eq(datasets_per_scale(gate), 5)
  assert_eq(
    datasets_per_scale(ProtocolPreset::QuickCheck.validated().protocol),
    1,
  )
}
