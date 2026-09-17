# Offline replay of retained manual labels and actual records, not a prose judge.
# Each full repetition supplies one rate to the existing Eval::Noise protocol.
# Canonical after is the revised arm; historical initial-candidate evidence stays
# separate. Ambiguous incidental assertions have explicit lower/upper bounds.
require "json"
require "digest"
require_relative "../../../lib/eval"
require_relative "../../../lib/eval/noise"

module PhysicalComparison
  ROOT = __dir__
  METRICS = {
    "expected_effect_missing" => "expected_recorded_outcome_missing",
    "core_contradiction" => "direct_core_physical_outcome_contradiction",
    "temporal_error" => "current_action_treated_as_earlier_completed_attempt"
  }.freeze

  def self.read(path) = JSON.parse(File.read(File.join(ROOT, path)))

  def self.valid_runs!(rows, cases)
    runs = rows.group_by { |row| row.fetch("rep") }.sort.to_h
    raise "Four complete repetitions required" if runs.length < Eval::Noise::MIN_RUNS
    runs.each_value do |run|
      raise "Missing or duplicate case" unless run.map { |row| row.fetch("case") }.sort == cases.sort
      raise "Failed call cannot count as success" if run.any? { |row| row["error"] || row["fallback"] || row.fetch("calls").any? { |call| call["error"] } }
    end
    runs
  end

  def self.rates(rows, metrics)
    rows.group_by { |row| row.fetch("rep") }.sort.to_h.transform_values do |run|
      metrics.to_h { |metric| [ metric, run.count { |row| row.fetch(metric) }.fdiv(run.length) ] }
    end
  end

  def self.physical(arm, spec, audit, cases)
    raw = read(spec.fetch("raw"))
    runs = valid_runs!(raw.fetch("results"), cases)
    raise "Wrong repetition metadata" unless raw.fetch("reps") == runs.length && !raw.fetch("preflight")
    labels = audit.fetch("physical").select { |row| row.fetch("arm") == spec.fetch("audit_arm") }
    raise "Missing or duplicate annotations" unless labels.length == raw.fetch("results").length && labels.map { |row| row.fetch("label") }.uniq.length == labels.length
    indexed = labels.to_h { |row| [ row.fetch("label"), row ] }
    rows = raw.fetch("results").map do |row|
      label = indexed.fetch("#{row.fetch('case')}:#{row.fetch('rep')}")
      %w[before after narration refusal interactions].each do |field|
        raise "Annotation evidence changed: #{arm}/#{field}" unless label.fetch(field) == row.fetch(field)
      end
      values = METRICS.transform_values do |field|
        value = label.fetch(field)
        raise "Missing binary judgment: #{field}" unless [ true, false ].include?(value)
        value
      end
      direct = label.fetch("direct_prose_state_contradiction")
      raise "Invalid incidental judgment" unless [ true, false, nil ].include?(direct)
      values.merge("rep" => row.fetch("rep"), "case" => row.fetch("case"),
        "incidental_contradiction" => direct == true && !values.fetch("core_contradiction"),
        "incidental_contradiction_including_ambiguities" => direct != false && !values.fetch("core_contradiction"),
        "incidental_ambiguity" => direct.nil?)
    end
    metrics = METRICS.keys + %w[incidental_contradiction incidental_contradiction_including_ambiguities]
    calls = raw.fetch("results").flat_map { |row| row.fetch("calls") }
    {
      source: raw.fetch("source"), corpus: raw.fetch("corpus"), fixtures: raw.fetch("fixtures_sha256"),
      audit_arm: spec.fetch("audit_arm"), samples: rows.length, repetitions: rates(rows, metrics),
      counts: metrics.to_h { |metric| [ metric, rows.count { |row| row.fetch(metric) } ] },
      ambiguities: rows.select { |row| row.fetch("incidental_ambiguity") }.map { |row| "#{row.fetch('case')}:#{row.fetch('rep')}" },
      excluding_friendly_acceptance: {
        samples: rows.count { |row| row.fetch("case") != "offer-requested-apple" },
        repetitions: rates(rows.reject { |row| row.fetch("case") == "offer-requested-apple" }, [ "expected_effect_missing" ])
      },
      cases: rows.group_by { |row| row.fetch("case") }.transform_values do |run|
        metrics.to_h { |metric| [ metric, run.count { |row| row.fetch(metric) } ] }
      end,
      calls: calls.length, models: calls.map { |row| row.fetch("actual_model") }.uniq
    }
  end

  def self.generation(spec, audit)
    raw = read(spec.fetch("raw"))
    runs = valid_runs!(raw.fetch("results"), %w[apothecary paper tools])
    raise "Preflight is not evidence" if raw.fetch("preflight")
    raise "Changed generation harness" unless raw.fetch("harness_sha256") == Digest::SHA256.file(File.join(ROOT, "generation/evaluate.rb")).hexdigest
    labels = audit.fetch("generation").select { |row| row.fetch("arm") == spec.fetch("audit_arm") }
    raise "Missing generation annotations" unless labels.length == raw.fetch("results").length
    indexed = labels.to_h { |row| [ row.fetch("label"), row ] }
    targets = []
    repetitions = runs.transform_values do |run|
      items = run.flat_map do |row|
        label = indexed.fetch("#{row.fetch('case')}:#{row.fetch('rep')}")
        raise "Changed generation description" unless label.fetch("description") == row.fetch("description")
        raise "Missing required object" unless label.fetch("required_objects_present")
        raise "Changed item count" unless label.fetch("items").length == row.fetch("items").length
        label.fetch("items").zip(row.fetch("items")).each do |annotation, item|
          %w[name description].each { |field| raise "Changed item" unless annotation.fetch(field) == item.fetch(field) }
          %w[use_kind combustible].each { |field| raise "Changed profile" unless annotation.fetch("observed_#{field}") == item.fetch(field) }
        end
        label.fetch("items").select { |item| item.fetch("primary_target") }
      end
      raise "Missing target objects" unless items.length == 6
      targets.concat(items)
      %w[complete_profile use_kind combustible].to_h do |field|
        [ "#{field}_incorrect", items.count { |item| !item.fetch("#{field}_correct") }.fdiv(items.length) ]
      end
    end
    { source: raw.fetch("source"), corpus: raw.fetch("corpus"), harness: raw.fetch("harness_sha256"),
      room_samples: raw.fetch("results").length, target_objects: targets.length, repetitions: repetitions,
      correct: %w[complete_profile use_kind combustible].to_h { |field| [ field, targets.count { |item| item.fetch("#{field}_correct") } ] },
      all_generated_objects: raw.fetch("results").sum { |row| row.fetch("items").length } }
  end

  def self.compare(left, right)
    left.fetch(:repetitions).values.first.keys.map do |metric|
      before = left.fetch(:repetitions).values.map { |row| row.fetch(metric) }
      after = right.fetch(:repetitions).values.map { |row| row.fetch(metric) }
      Eval::Noise.compare(metric, before, after).to_h.merge(before_rates: before, after_rates: after)
    end
  end

  def self.run
    manifest = read("manifest.json")
    manifest.fetch("files").each do |path, receipt|
      raise "Changed evidence: #{path}" unless Digest::SHA256.file(File.join(ROOT, path)).hexdigest == receipt.fetch("sha256")
    end
    audit = read("manual-audit.json")
    cases = read("cases.json").map { |row| row.fetch("id") }
    manifest.values_at("physical_arms", "generation_arms").each do |arms|
      arms.each_value do |spec|
        raise "Wrong source manifest" unless read(spec.fetch("raw")).fetch("source") == read(spec.fetch("source_manifest")).fetch("sha256")
      end
    end
    physical = manifest.fetch("physical_arms").to_h { |arm, spec| [ arm, physical(arm, spec, audit, cases) ] }
    raise "Changed physical corpus/fixtures" unless physical.values.map { |arm| arm.values_at(:corpus, :fixtures) }.uniq.one?
    raise "Changed fixture source" unless physical.fetch("before").fetch(:fixtures) == Digest::SHA256.file(File.join(ROOT, "fixtures.rb")).hexdigest
    raise "Changed case source" unless physical.fetch("before").fetch(:corpus) == Digest::SHA256.hexdigest(JSON.generate(read("cases.json")))
    generation = manifest.fetch("generation_arms").to_h { |arm, spec| [ arm, generation(spec, audit) ] }
    raise "Changed generation corpus/harness" unless generation.values.map { |arm| arm.values_at(:corpus, :harness) }.uniq.one?
    verdicts = {
      physical: compare(physical.fetch("before"), physical.fetch("after")),
      physical_excluding_friendly_acceptance: compare(physical.fetch("before").fetch(:excluding_friendly_acceptance), physical.fetch("after").fetch(:excluding_friendly_acceptance)),
      generation: compare(generation.fetch("before"), generation.fetch("after")),
      initial_candidate_vs_revised: compare(physical.fetch("initial_candidate"), physical.fetch("after"))
    }
    result = { physical: physical, generation: generation, verdicts: verdicts,
      limitations: audit.fetch("bounded_findings") + [
        "Manual labels were read with arm names visible; comparison replays those judgments and does not independently judge prose.",
        "Incidental counts exclude core effect contradictions. Their lower bound counts confirmed conflicts; upper bound also counts the one ambiguous initial-candidate cast phrase, with seven cases retained in every denominator.",
        "Friendly acceptance is a fixture expectation, not an engine-validity requirement; its exclusion is also compared.",
        "Generation target profiles are six specified object types in three seeded teasers, not general room-generation realism. Baseline profile fields were unavailable and defaulted to ordinary/false.",
        "Four repetitions of one model on these fixtures do not establish general realism. Several comparisons are exploratory; no multiple-comparison correction is applied."
      ] }
    File.write(File.join(ROOT, "comparison.json"), JSON.pretty_generate(result) + "\n")
    puts JSON.pretty_generate(verdicts)
  end
end

PhysicalComparison.run
