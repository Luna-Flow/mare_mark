///|
fn observation_line(
  case_id : String,
  implementation : String,
  scale : String,
  block : Int,
  elapsed_us : Double,
  dataset? : Int = 0,
  phase? : String = "confirmatory",
  valid? : Bool = true,
) -> String {
  Json::object({
    "type": Json::string("observation"),
    "case": Json::string(case_id),
    "implementation": Json::string(implementation),
    "dataset_id": Json::number(dataset.to_double()),
    "block_id": Json::number(block.to_double()),
    "scale": Json::string(scale),
    "phase": Json::string(phase),
    "elapsed_us": Json::number(elapsed_us),
    "valid": Json::boolean(valid),
  }).stringify()
}

///|
fn test_protocol(
  policy : @model.OutlierPolicy,
  practical_delta_pct : Double,
) -> @model.RunProtocol {
  @model.RunProtocol::new(
    @model.ExperimentDesign::HierarchicalDatasetsAndRepeats,
    0,
    None,
    @model.CalibrationProtocol::new(
      1000.0,
      1,
      1000,
      100000.0,
      @model.BatchPolicy::PerImplementation,
    ),
    practical_delta_pct,
    @model.OrderPolicy::BalancedBlocks(1),
    policy,
    @model.ValidationCoverage::EveryDataset,
    0,
    8,
  )
}

///|
fn summary_line(protocol : @model.RunProtocol?, seed : String?) -> String {
  let fields : Map[String, Json] = {
    "type": Json::string("summary"),
    "run_id": Json::string("compare"),
  }
  if protocol is Some(protocol) {
    fields["protocol"] = @event.protocol_json(protocol)
  }
  if seed is Some(seed) {
    fields["seed"] = Json::string(seed)
  }
  Json::object(fields).stringify()
}

///|
/// Observations of `implementation` at scale "8" of case "c", one per block.
fn series(implementation : String, times : Array[Double]) -> Array[String] {
  times.mapi((block, time) => {
    observation_line("c", implementation, "8", block, time)
  })
}

///|
fn comparisons_of(
  lines : Array[String],
  baseline? : String,
) -> @ir.ComparisonReport {
  match document_from_jsonl(lines.join("\n"), baseline?) {
    Ok(document) => document.comparisons
    Err(message) => abort(message)
  }
}

///|
test "comparisons pair by block across datasets sharing a scale" {
  // Three datasets share scale 8 and every block measures one dataset for
  // both implementations. Lines are out of order; pairing follows block_id.
  let lines = [
    observation_line("c", "a", "8", 0, 10.0, dataset=0),
    observation_line("c", "b", "8", 2, 27.0, dataset=2),
    observation_line("c", "a", "8", 1, 20.0, dataset=1),
    "{\"type\":\"validation\",\"status\":\"valid\",\"implementation\":\"b\",\"scale\":\"8\",\"validation_scope\":\"measurement\",\"repetition_id\":0,\"block_id\":1,\"dataset_id\":1}",
    observation_line("c", "b", "8", 0, 9.0, dataset=0),
    observation_line("c", "a", "8", 2, 30.0, dataset=2),
    observation_line("c", "b", "8", 1, 18.0, dataset=1),
    // Block 3 has no candidate, block 4 two candidates: both are incomplete.
    observation_line("c", "a", "8", 3, 40.0, dataset=2),
    observation_line("c", "a", "8", 4, 50.0, dataset=2),
    observation_line("c", "b", "8", 4, 45.0, dataset=2),
    observation_line("c", "b", "8", 4, 46.0, dataset=2),
    // An invalid observation or another phase never enters a pair.
    observation_line("c", "b", "8", 3, 1.0, dataset=2, valid=false),
    observation_line("c", "b", "8", 5, 1.0, phase="exploratory"),
    observation_line("c", "a", "8", 5, 1.0, phase="exploratory"),
  ]
  let report = comparisons_of(lines)
  assert_eq(report.rows.length(), 1)
  let row = report.rows[0]
  assert_eq(row.case_id, "c")
  assert_eq(row.scale, "8")
  assert_eq(row.baseline, "a")
  assert_eq(row.candidate, "b")
  assert_eq(row.blocks_used, 3)
  assert_eq(row.blocks_incomplete, 2)
  assert_eq(row.blocks_outliers, 0)
  guard row.estimate is Some(estimate) else { abort("expected an estimate") }
  assert_eq(estimate.baseline_median_us, 20.0)
  assert_eq(estimate.candidate_median_us, 18.0)
  assert_eq(estimate.median_delta_us, -2.0)
  assert_eq(estimate.relative_delta_pct, -10.0)
  assert_true(row.decision is Faster)
  assert_eq(row.reason, "")
  // A failed validation of a dataset drops that implementation's blocks on it.
  let failed = lines.copy()
  failed.push(
    "{\"type\":\"validation\",\"status\":\"invalid\",\"case\":\"c\",\"implementation\":\"b\",\"dataset_id\":1,\"validation_scope\":\"measurement\",\"block_id\":1}",
  )
  let row = comparisons_of(failed).rows[0]
  assert_eq(row.blocks_used, 2)
  assert_eq(row.blocks_incomplete, 3)
  assert_true(row.decision is Unknown)
  assert_eq(row.reason, "2 usable blocks; at least 3 are needed")
}

///|
test "paired blocks keep ascending block order and count incomplete blocks" {
  let group = (
    implementation : String,
    times : Array[Double],
    blocks : Array[Int?],
  ) => {
    scale: "1",
    scale_source: Recorded,
    implementation,
    elapsed_us: times,
    block_ids: blocks,
  }
  let baseline = group("a", [1.0, 2.0, 3.0, 4.0], [
    Some(5),
    Some(1),
    None,
    Some(7),
  ])
  let candidate = group("b", [10.0, 20.0, 30.0], [Some(1), Some(9), Some(5)])
  let (pairs, incomplete) = paired_blocks(Some(baseline), candidate)
  assert_true(pairs == [(1, 2.0, 10.0), (5, 1.0, 30.0)])
  assert_eq(incomplete, 2)
  let (pairs, incomplete) = paired_blocks(None, candidate)
  assert_true(pairs.is_empty())
  assert_eq(incomplete, 3)
}

///|
test "the baseline defaults to the first implementation of each case" {
  let lines = [
    observation_line("c", "slow", "8", 0, 20.0),
    observation_line("c", "fast", "8", 0, 10.0),
    observation_line("c", "mid", "8", 0, 15.0),
    observation_line("d", "mid", "8", 0, 15.0),
    observation_line("d", "fast", "8", 0, 10.0),
  ]
  let rows = comparisons_of(lines).rows
  assert_true(
    rows.map(row => row.case_id + ":" + row.baseline + "->" + row.candidate) ==
    ["c:slow->fast", "c:slow->mid", "d:mid->fast"],
  )
  let rows = comparisons_of(lines, baseline="fast").rows
  assert_true(
    rows.map(row => row.case_id + ":" + row.baseline + "->" + row.candidate) ==
    ["c:fast->slow", "c:fast->mid", "d:fast->mid"],
  )
  // A baseline missing from a case leaves its rows undecided.
  let rows = comparisons_of(lines, baseline="slow").rows
  assert_eq(rows.length(), 4)
  assert_true(rows[2].case_id == "d" && rows[2].decision is Unknown)
  assert_eq(
    rows[2].reason,
    "baseline has no confirmatory observations at this scale",
  )
  assert_eq(rows[2].blocks_incomplete, 1)
  assert_true(
    document_from_jsonl(lines.join("\n"), baseline="nope")
    is Err(
      "unknown baseline 'nope'; implementations in the record: slow, fast, mid"
    ),
  )
  assert_true(
    document_from_jsonl(
      "{\"type\":\"validation_failure\",\"implementation\":\"x\"}",
      baseline="x",
    )
    is Err("unknown baseline 'x'; implementations in the record: none"),
  )
}

///|
test "the outlier policy applies to paired deltas, not to raw times" {
  // Block 3 is slow for both implementations (a shared block effect) and
  // block 5 only for the candidate. Filtering raw times would drop block 3;
  // filtering the deltas keeps it and removes block 5.
  let baseline = [10.0, 10.2, 9.9, 30.0, 10.1, 10.0, 9.8, 10.3]
  let candidate = [9.0, 9.1, 8.9, 29.1, 9.0, 25.0, 8.8, 9.2]
  let lines = series("a", baseline)
  lines.append(series("b", candidate))
  lines.push(summary_line(Some(test_protocol(TukeyFence, 2.0)), Some("1")))
  let report = comparisons_of(lines)
  assert_eq(report.outlier_policy, "tukey_fence")
  let row = report.rows[0]
  assert_eq(row.blocks_used, 7)
  assert_eq(row.blocks_outliers, 1)
  assert_eq(row.blocks_incomplete, 0)
  let pairs = filter_pairs(
    baseline.mapi((block, time) => (block, time, candidate[block])),
    TukeyFence,
  )
  assert_true(pairs.map(pair => pair.0) == [0, 1, 2, 3, 4, 6, 7])
  assert_true(row.decision is Faster)
  // Without a policy every complete block is used.
  lines[lines.length() - 1] = summary_line(
    Some(test_protocol(ReportOnly, 2.0)),
    Some("1"),
  )
  let row = comparisons_of(lines).rows[0]
  assert_eq(row.blocks_used, 8)
  assert_eq(row.blocks_outliers, 0)
}

///|
test "settings come from the recorded protocol or are stated as defaults" {
  let lines = series("a", [10.0, 11.0, 12.0])
  lines.append(series("b", [10.0, 11.0, 12.0]))
  let fallback = comparisons_of(lines)
  assert_eq(fallback.practical_delta_pct, 1.0)
  assert_eq(fallback.outlier_policy, "report_only")
  assert_eq(fallback.run_seed, 0UL)
  assert_true(!fallback.protocol_recorded && !fallback.seed_recorded)
  assert_true(
    fallback.note.has_prefix(
      "The record has no protocol: decision threshold ±1 % and outlier policy report_only (applied to the paired deltas) are defaults; the record has no seed: run seed 0 is a default.",
    ),
  )
  assert_eq(fallback.resamples, 10000)
  assert_eq(fallback.confidence_pct, 95.0)
  assert_eq(fallback.min_blocks, 3)
  lines.push(summary_line(Some(test_protocol(MADTrim, 5.0)), Some("99")))
  let recorded = comparisons_of(lines)
  assert_eq(recorded.practical_delta_pct, 5.0)
  assert_eq(recorded.outlier_policy, "mad_trim")
  assert_eq(recorded.run_seed, 99UL)
  assert_true(recorded.protocol_recorded && recorded.seed_recorded)
  assert_true(
    recorded.note.has_prefix(
      "Decision threshold ±5 % and outlier policy mad_trim (applied to the paired deltas) from the recorded protocol; run seed 99 from the record.",
    ),
  )
  assert_true(recorded.note.contains("10000 resamples (report defaults)"))
  // A protocol without a seed still says where the seed comes from.
  lines[lines.length() - 1] = summary_line(
    Some(test_protocol(MADTrim, 5.0)),
    None,
  )
  assert_true(
    comparisons_of(lines).note.contains(
      "the record has no seed: run seed 0 is a default",
    ),
  )
  // A malformed protocol or seed is an error, not a silent default.
  lines[lines.length() - 1] = "{\"type\":\"summary\",\"protocol\":{}}"
  assert_true(
    document_from_jsonl(lines.join("\n"))
    is Err("invalid protocol at line 7: protocol.calibration: missing"),
  )
  for seed in ["\"007\"", "\"-1\"", "7"] {
    lines[lines.length() - 1] = "{\"type\":\"summary\",\"seed\":" + seed + "}"
    assert_true(
      document_from_jsonl(lines.join("\n")) is Err("invalid seed at line 7"),
    )
  }
}

///|
test "row seeds are derived from the run seed and the row identity" {
  let lines = series("a", [10.0, 11.0, 12.0, 13.0])
  lines.append(series("b", [9.0, 10.0, 11.5, 12.0]))
  lines.append(series("c", [12.0, 13.0, 14.0, 15.0]))
  lines.push(summary_line(Some(test_protocol(ReportOnly, 1.0)), Some("99")))
  let source = lines.join("\n")
  guard document_from_jsonl(source) is Ok(first) else { abort("document") }
  guard document_from_jsonl(source) is Ok(second) else { abort("document") }
  assert_eq(plot_json(first), plot_json(second))
  let rows = first.comparisons.rows
  assert_eq(rows[0].seed, comparison_seed(99UL, "c", "8", "a", "b"))
  assert_eq(rows[1].seed, comparison_seed(99UL, "c", "8", "a", "c"))
  assert_true(rows[0].seed != rows[1].seed)
  assert_true(
    comparison_seed(98UL, "c", "8", "a", "b") != rows[0].seed &&
    comparison_seed(99UL, "c", "8", "b", "a") != rows[0].seed,
  )
  // 64-bit FNV-1a of "mare_mark/compare/v1␟0␟␟␟␟", computed independently.
  assert_eq(comparison_seed(0UL, "", "", "", ""), 3314728152632147673UL)
  assert_true(
    plot_json(first).contains("\"seed\":\"" + rows[0].seed.to_string() + "\""),
  )
}

///|
test "an exact tie is equivalent even at a zero threshold" {
  let times = [10.0, 11.0, 12.0, 13.0, 14.0]
  let lines = series("a", times)
  lines.append(series("b", times))
  lines.push(summary_line(Some(test_protocol(ReportOnly, 0.0)), None))
  let row = comparisons_of(lines).rows[0]
  assert_true(row.decision is Equivalent)
  guard row.estimate is Some(estimate) && row.interval is Some(interval) else {
    abort("expected an estimate and an interval")
  }
  assert_eq(estimate.relative_delta_pct, 0.0)
  assert_eq(estimate.speedup, 1.0)
  assert_eq(interval.low_us, 0.0)
  assert_eq(interval.high_pct, 0.0)
}

///|
test "clear margins are faster or slower with an interval on the same side" {
  let baseline = [10.0, 10.4, 9.8, 10.1, 10.2, 9.9]
  let lines = series("base", baseline)
  lines.append(series("half", baseline.map(time => time * 0.5)))
  lines.append(series("double", baseline.map(time => time * 2.0)))
  lines.push(summary_line(Some(test_protocol(ReportOnly, 2.0)), Some("5")))
  let rows = comparisons_of(lines).rows
  assert_true(rows[0].candidate == "half" && rows[0].decision is Faster)
  assert_true(rows[1].candidate == "double" && rows[1].decision is Slower)
  guard rows[0].interval is Some(faster) && rows[1].interval is Some(slower) else {
    abort("expected intervals")
  }
  assert_true(faster.high_pct < -2.0 && faster.low_pct <= faster.high_pct)
  assert_true(slower.low_pct > 2.0)
  assert_true(faster.low_us < 0.0 && slower.low_us > 0.0)
  guard rows[1].estimate is Some(estimate) else { abort("expected estimate") }
  assert_eq(estimate.relative_delta_pct, 100.0)
  assert_eq(estimate.speedup, 0.5)
}

///|
test "undecidable comparisons are rows with a reason" {
  // Too few blocks.
  let lines = series("a", [1.0, 2.0])
  lines.append(series("b", [1.0, 2.0]))
  let row = comparisons_of(lines).rows[0]
  assert_true(row.decision is Unknown && row.interval is None)
  assert_true(row.estimate is Some(_))
  assert_eq(row.reason, "2 usable blocks; at least 3 are needed")
  // A zero baseline has no relative delta.
  let lines = series("a", [0.0, 0.0, 0.0])
  lines.append(series("b", [1.0, 2.0, 3.0]))
  let row = comparisons_of(lines).rows[0]
  assert_true(row.decision is Invalid)
  assert_eq(
    row.reason,
    "baseline median is not positive; the relative delta is undefined",
  )
  // A threshold the stats package rejects.
  let lines = series("a", [1.0, 2.0, 3.0])
  lines.append(series("b", [1.0, 2.0, 3.0]))
  lines.push(summary_line(Some(test_protocol(ReportOnly, -1.0)), None))
  let row = comparisons_of(lines).rows[0]
  assert_true(row.decision is Invalid && row.interval is Some(_))
  assert_eq(
    row.reason,
    "practical_delta_pct -1 is not a finite, non-negative threshold",
  )
  // A non-finite time reaches the bootstrap, which rejects it.
  let lines = series("a", [1.0, 2.0, 3.0])
  lines.push(observation_line("c", "b", "8", 0, 1.0))
  lines.push(observation_line("c", "b", "8", 1, 2.0))
  lines.push(
    "{\"type\":\"observation\",\"case\":\"c\",\"implementation\":\"b\",\"dataset_id\":0,\"block_id\":2,\"scale\":\"8\",\"elapsed_us\":1e999}",
  )
  let row = comparisons_of(lines).rows[0]
  assert_true(row.decision is Invalid && row.interval is None)
  assert_eq(row.reason, "bootstrap: paired delta 2 is not finite")
  // Records without block_id cannot be paired, and the note says so.
  let report = comparisons_of([
    "{\"type\":\"observation\",\"case\":\"c\",\"implementation\":\"a\",\"dataset_id\":0,\"elapsed_us\":1.0}",
    "{\"type\":\"observation\",\"case\":\"c\",\"implementation\":\"b\",\"dataset_id\":0,\"elapsed_us\":2.0}",
  ])
  let row = report.rows[0]
  assert_eq(row.scale, "dataset_id 0")
  assert_true(row.decision is Unknown && row.estimate is None)
  assert_eq(row.reason, "block_id not recorded; observations cannot be paired")
  assert_true(
    comparison_cells(row)[4:9].to_owned() == ["-", "-", "-", "-", "Unknown"],
  )
  assert_true(
    report.note.has_suffix(
      " 2 confirmatory observations have no block_id and cannot be paired.",
    ),
  )
  assert_true(
    comparison_note(comparison_settings(None, None), 1).has_suffix(
      " 1 confirmatory observation has no block_id and cannot be paired.",
    ),
  )
  assert_true(
    document_from_jsonl(
      "{\"type\":\"observation\",\"implementation\":\"a\",\"dataset_id\":0,\"elapsed_us\":1.0,\"block_id\":\"x\"}",
    )
    is Err("invalid block_id at line 1"),
  )
}

///|
test "bootstrap errors and decisions have readable names" {
  assert_eq(bootstrap_error_text(EmptySamples), "no paired deltas")
  assert_eq(
    bootstrap_error_text(MismatchedPairs(2, 3)),
    "mismatched pairs (2 baseline, 3 candidate)",
  )
  assert_eq(
    bootstrap_error_text(InvalidResamples(0)),
    "invalid resample count 0",
  )
  assert_eq(
    bootstrap_error_text(InvalidConfidence(100.0)),
    "invalid confidence 100",
  )
  assert_eq(
    bootstrap_error_text(NonFiniteSample(1)),
    "paired delta 1 is not finite",
  )
  let decisions : Array[@ir.ComparisonDecision] = [
    Faster,
    Slower,
    Equivalent,
    Unknown,
    Invalid,
  ]
  assert_true(
    decisions.map(@ir.ComparisonDecision::text) ==
    ["faster", "slower", "equivalent", "unknown", "invalid"],
  )
  assert_true(
    decisions.map(decision_label) ==
    ["Faster", "Slower", "Equivalent", "Unknown", "Invalid"],
  )
  assert_true(
    decision_of(
      @stats.compare_paired(
        "a",
        "b",
        [],
        [],
        1.0,
        @model.confirmatory_interval(),
      ).decision,
    )
    is Unknown,
  )
  assert_true(
    decision_of(
      @stats.compare_paired(
        "a",
        "b",
        [1.0],
        [],
        1.0,
        @model.confirmatory_interval(),
      ).decision,
    )
    is Invalid,
  )
  assert_true(
    number_json(0.0 / 0.0) == Json::string("NaN") &&
    number_json(1.0 / 0.0) == Json::string("Infinity") &&
    number_json(-1.0 / 0.0) == Json::string("-Infinity"),
  )
}

///|
test "comparisons render as an escaped HTML section before the plots" {
  let lines = [
    observation_line("<c&>", "a\"<", "8", 0, 10.0),
    observation_line("<c&>", "b'>", "8", 0, 5.0),
    observation_line("<c&>", "a\"<", "8", 1, 10.0),
    observation_line("<c&>", "b'>", "8", 1, 5.0),
    observation_line("<c&>", "a\"<", "8", 2, 10.0),
    observation_line("<c&>", "b'>", "8", 2, 5.0),
    observation_line("<c&>", "z", "8", 0, 5.0),
  ]
  guard document_from_jsonl(lines.join("\n")) is Ok(document) else {
    abort("document")
  }
  let page = html(document)
  assert_true(page.contains("<h2 id=\"comparisons-title\">Comparisons</h2>"))
  assert_true(page.contains("<td>&lt;c&amp;&gt;</td>"))
  assert_true(page.contains("<td>a&quot;&lt;</td><td>b&apos;&gt;</td>"))
  assert_true(!page.contains("<c&>") && !page.contains("a\"<"))
  assert_true(
    page.contains("<span class=\"decision decision-faster\">Faster</span></td>"),
  )
  assert_true(
    page.contains(
      "<span class=\"decision decision-unknown\">Unknown</span><span class=\"reason\">1 usable block; at least 3 are needed</span>",
    ),
  )
  assert_true(page.contains("<td class=\"num\">-50 %</td>"))
  assert_true(page.contains("<td class=\"num\">3 / 0 / 0</td>"))
  assert_true(
    page.find("Comparisons").unwrap() < page.find("<figure>").unwrap(),
  )
  let json = plot_json(document)
  assert_true(json.contains("\"decision\":\"faster\""))
  assert_true(json.contains("\"protocol_source\":\"default\""))
  assert_true(json.contains("\"interval\":null"))
  // Without rows there is no section and no text table.
  let single = document_from_jsonl(observation_line("c", "a", "8", 0, 1.0)).unwrap()
  assert_true(!html(single).contains("Comparisons"))
  assert_eq(comparisons_text(single), "")
}

///|
test "comparisons print as an aligned plain-text table" {
  let lines = series("a", [10.0, 10.0, 10.0])
  lines.append(series("longer-name", [5.0, 5.0, 5.0]))
  guard document_from_jsonl(lines.join("\n")) is Ok(document) else {
    abort("document")
  }
  let text = comparisons_text(document)
  let rows = text.split("\n").map(line => line.to_owned()).collect()
  assert_eq(rows.length(), 4)
  assert_eq(rows[0], "Comparisons")
  assert_eq(rows[1], document.comparisons.note)
  assert_true(
    rows[2].has_prefix("case  scale  baseline  candidate    baseline µs/op"),
  )
  assert_true(rows[3].has_prefix("c     8      a         longer-name  10  "))
  // Columns line up: the decision starts at the same offset in both lines.
  assert_eq(rows[2].find("decision"), rows[3].find("Faster"))
  assert_true(rows[3].contains("[-50 %, -50 %]"))
  assert_true(signed_number(0.0) == "0" && signed_number(1.5) == "+1.5")
}
