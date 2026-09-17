# Freeze and compare the completed final-classifier physical confirmation.
# This is offline: it reads stored turns, manual labels and receipts only.
require "json"
require "digest"
require_relative "../../../../lib/eval"
require_relative "../../../../lib/eval/noise"

module FinalPhysicalConfirmation
  extend self

  ROOT = Pathname(__dir__)
  ORIGINAL = ROOT.join("../../physical-20260910").expand_path
  RAW = ROOT.join("physical-after.json")
  AUDIT = ROOT.join("manual-audit.json")
  RECEIPTS = ROOT.join("receipts.json")
  PRIOR_DIGESTS = {
    "physical-before.json" => "93b9478bbae25822756733c9b8ec38dfe0e86bec018e2975ef31aa67b1496e79",
    "physical-after.json" => "5351dcd6486cf9adbf828bcec75727e2aefef719d8c69f3492ac85e87fa0ccc0",
    "manual-audit.json" => "3aef6eae702040faba8c07a48b410b15785ef9172724428ebf44902e65ff4731",
    "cases.json" => "84b7ac897108b5227cc21a3860ef6c0cf93a050196c7558cd2922ecc01f5f92f"
  }.freeze
  PHYSICAL_METRICS = %w[
    expected_recorded_outcome_missing
    direct_core_physical_outcome_contradiction
    current_action_treated_as_earlier_completed_attempt
    incidental_contradiction
  ].freeze
  SAFETY_METRICS = %w[
    wrong_target_selected
    engine_record_mismatch
  ].freeze
  METRICS = (PHYSICAL_METRICS + SAFETY_METRICS).freeze
  EVIDENCE_FIELDS = %w[before after narration refusal interactions resolved_action calls].freeze

  def read(path) = JSON.parse(path.read)
  def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))

  def verify_prior_evidence!
    PRIOR_DIGESTS.each do |path, expected|
      raise "Changed prior evidence: #{path}" unless Digest::SHA256.file(ORIGINAL.join(path)).hexdigest == expected
    end
  end

  def final_rows
    raw = read(RAW)
    audit = read(AUDIT)
    raise "Final evidence changed" unless Digest::SHA256.file(RAW).hexdigest == audit.dig("source", "sha256")
    raise "Live result required" if raw.fetch("preflight") || raw.fetch("reps") != 4
    raise "Wrong model" unless raw.values_at("model", "provider") == [ "mistralai/mistral-medium-3.1", "openrouter" ]
    baseline = read(ORIGINAL.join("physical-before.json"))
    raise "Corpus or fixtures changed" unless raw.values_at("corpus", "fixtures_sha256") == baseline.values_at("corpus", "fixtures_sha256")
    cases = read(ORIGINAL.join("cases.json")).map { |row| row.fetch("id") }
    runs = raw.fetch("results").group_by { |row| row.fetch("rep") }
    raise "Four complete repetitions required" unless runs.keys.sort == (1..4).to_a
    runs.each_value { |run| raise "Missing or duplicate case" unless run.map { |row| row.fetch("case") }.sort == cases.sort }
    raise "A failed call cannot count" if raw.fetch("results").any? { |row| row["error"] || row["fallback"] || row.fetch("calls").any? { |call| call["error"] } }

    labels = audit.fetch("rows").to_h { |row| [ row.fetch("label"), row ] }
    raise "Missing or duplicate audit row" unless labels.size == raw.fetch("results").size
    defaults = audit.fetch("defaults")
    raw.fetch("results").map do |row|
      label = labels.fetch("#{row.fetch('case')}:#{row.fetch('rep')}")
      evidence = row.slice(*EVIDENCE_FIELDS)
      raise "Changed audit evidence: #{label.fetch('label')}" unless digest(evidence) == label.fetch("evidence_sha256")
      values = defaults.merge(label)
      METRICS.first(3).each { |metric| raise "Missing binary label: #{metric}" unless [ true, false ].include?(values.fetch(metric)) }
      %w[wrong_target_selected engine_record_mismatch].each { |metric| raise "Missing binary label: #{metric}" unless [ true, false ].include?(values.fetch(metric)) }
      direct = values.fetch("direct_prose_state_contradiction")
      core = values.fetch("direct_core_physical_outcome_contradiction")
      values.slice(*METRICS).merge("rep" => row.fetch("rep"), "case" => row.fetch("case"),
        "incidental_contradiction" => direct && !core)
    end
  end

  def prior_rows(arm)
    audit = read(ORIGINAL.join("manual-audit.json"))
    audit.fetch("physical").select { |row| row.fetch("arm") == arm }.map do |row|
      { "rep" => row.fetch("rep"), "case" => row.fetch("case"),
        "expected_recorded_outcome_missing" => row.fetch("expected_recorded_outcome_missing"),
        "direct_core_physical_outcome_contradiction" => row.fetch("direct_core_physical_outcome_contradiction"),
        "current_action_treated_as_earlier_completed_attempt" => row.fetch("current_action_treated_as_earlier_completed_attempt"),
        "incidental_contradiction" => row.fetch("direct_prose_state_contradiction") == true && !row.fetch("direct_core_physical_outcome_contradiction"),
        "wrong_target_selected" => false, "engine_record_mismatch" => false }
    end
  end

  def rates(rows, metrics)
    rows.group_by { |row| row.fetch("rep") }.sort.to_h.transform_values do |run|
      metrics.to_h { |metric| [ metric, run.count { |row| row.fetch(metric) }.fdiv(run.length) ] }
    end
  end

  def summarize(rows, metrics)
    { samples: rows.size, repetitions: rates(rows, metrics), counts: metrics.to_h { |metric| [ metric, rows.count { |row| row.fetch(metric) } ] },
      cases: rows.group_by { |row| row.fetch("case") }.transform_values do |run|
        metrics.to_h { |metric| [ metric, run.count { |row| row.fetch(metric) } ] }
      end }
  end

  def compare(left, right, metrics)
    left_rates = rates(left, metrics).values
    right_rates = rates(right, metrics).values
    metrics.map do |metric|
      before = left_rates.map { |run| run.fetch(metric) }
      after = right_rates.map { |run| run.fetch(metric) }
      Eval::Noise.compare(metric, before, after).to_h.merge(before_rates: before, after_rates: after)
    end
  end

  def receipt_summary(raw)
    calls = raw.fetch("results").flat_map { |row| row.fetch("calls") }
    raise "Expected 60 calls" unless calls.size == 60
    raise "Model rotation" unless calls.map { |call| call.fetch("actual_model") }.uniq == [ raw.fetch("model") ]
    raise "Provider rotation" unless calls.map { |call| call.fetch("provider") }.uniq == [ raw.fetch("provider") ]
    {
      source: { path: "physical-after.json", sha256: Digest::SHA256.file(RAW).hexdigest },
      calls: calls.size, purposes: calls.group_by { |call| call.fetch("purpose") }.transform_values(&:size),
      actual_models: calls.map { |call| call.fetch("actual_model") }.tally,
      providers: calls.map { |call| call.fetch("provider") }.tally,
      provider_cost_reported_calls: calls.count { |call| !call["provider_cost_usd"].nil? },
      provider_cost_missing_calls: calls.count { |call| call["provider_cost_usd"].nil? },
      provider_cost_reported_usd: calls.sum { |call| call["provider_cost_usd"].to_f }.round(8),
      registry_cost_usd: calls.sum { |call| call.fetch("registry_cost_usd") }.round(8),
      input_tokens: calls.sum { |call| call.fetch("input_tokens") },
      output_tokens: calls.sum { |call| call.fetch("output_tokens") },
      cached_tokens: calls.sum { |call| call.fetch("cached_tokens") },
      call_receipts_sha256: digest(calls),
      accounting: {
        method: "The shared ledger charged provider-reported cost where present and the admitted reservation upper bound for streamed calls whose provider omitted cost metadata.",
        settled_entries: 60, reserved_entries: 0, accounted_usd: 0.106813,
        selected_ledger_entries_sha256: "2432da230d6c0f32e008feaa080859500559d307febf01df46cd204a8302c6ff",
        cumulative_ceiling_usd: 5.0, shared_accounted_usd_after_arm: 4.19184,
        authorization: "yes, just raise it to $5"
      }
    }
  end

  def run
    verify_prior_evidence!
    raw = read(RAW)
    final = final_rows
    before = prior_rows("before")
    revised = prior_rows("revised")
    result = {
      comparison_type: "same model and seven-case corpus; initial engine baseline and prior revised prompt compared with the final classifier prompt",
      arms: { initial_baseline: summarize(before, PHYSICAL_METRICS), prior_revised: summarize(revised, METRICS),
              final_classifier: summarize(final, METRICS) },
      verdicts: { initial_baseline_to_final: compare(before, final, PHYSICAL_METRICS),
                  prior_revised_to_final: compare(revised, final, METRICS) },
      findings: [
        "All 28 final turns selected the intended supported target or explicitly refused the unsupported stone burn; no wrong-target selection reached state.",
        "All 28 engine records satisfied their fixture expectations, including two failed and two successful persisted pry checks.",
        "Core effect contradictions remained 0/28. Three incidental inventory contradictions remained: empty vial claims in drink repetitions 2 and 4, and a dropped-lever claim in pry repetition 1.",
        "Compared with the prior revised arm, total incidental contradictions stayed 3/28 and merely moved between repetitions; every measured difference is NOISE."
      ],
      limitations: read(AUDIT).fetch("limitations") + [
        "The initial baseline predates engine-owned physical actions, so wrong-target and engine-record-mismatch rates are compared only between the prior revised and final arms.",
        "Several exploratory comparisons are shown without a multiple-comparison correction."
      ]
    }
    File.write(ROOT.join("comparison.json"), JSON.pretty_generate(result) + "\n")
    File.write(RECEIPTS, JSON.pretty_generate(receipt_summary(raw)) + "\n")
    provenance = {
      generated_by: "finalize.rb", generated_offline: true,
      sources: {
        "physical-after.json" => Digest::SHA256.file(RAW).hexdigest,
        "manual-audit.json" => Digest::SHA256.file(AUDIT).hexdigest,
        "physical-20260910/physical-before.json" => Digest::SHA256.file(ORIGINAL.join("physical-before.json")).hexdigest,
        "physical-20260910/physical-after.json" => Digest::SHA256.file(ORIGINAL.join("physical-after.json")).hexdigest,
        "physical-20260910/manual-audit.json" => Digest::SHA256.file(ORIGINAL.join("manual-audit.json")).hexdigest,
        "physical-20260910/cases.json" => Digest::SHA256.file(ORIGINAL.join("cases.json")).hexdigest
      },
      source_sha256: raw.fetch("source"), corpus_sha256: raw.fetch("corpus"), fixtures_sha256: raw.fetch("fixtures_sha256"),
      model: raw.fetch("model"), provider: raw.fetch("provider"), repetitions: raw.fetch("reps"),
      output_sha256: {
        "comparison.json" => Digest::SHA256.file(ROOT.join("comparison.json")).hexdigest,
        "receipts.json" => Digest::SHA256.file(RECEIPTS).hexdigest
      }
    }
    File.write(ROOT.join("run-provenance.json"), JSON.pretty_generate(provenance) + "\n")
    puts JSON.pretty_generate(result.fetch(:verdicts))
  end
end

FinalPhysicalConfirmation.run
