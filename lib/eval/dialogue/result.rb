# State checks are re-read from frozen records. Human contradiction annotations
# are an input, never an automated judge. Missing judgments stay unavailable;
# excerpt and reason are required for positives, under the retained protocol.
# Facts immediately after speech are distinct from facts after the follow-up
# move or attack: narrating a truce before a later attack is not contradiction.
class Eval::Dialogue::Result
  METRICS = %w[state_failure exchange_failure contradiction reaction_words narration_words].freeze
  attr_reader :data, :annotations

  def self.load(directory, annotations: nil)
    new(JSON.parse(Pathname.new(directory).join(Eval::Dialogue::RESULTS).read), annotations: annotations)
  end

  def initialize(data, annotations: nil)
    @data = data
    @annotations = annotations || {}
    validate_annotations!
  end

  def rows = data.fetch("rows")
  def checks(row) = row.fetch("expected").map { |key, value| [ key, row.fetch("facts")[key] == value ] }.to_h
  def judgment(row) = annotations["#{row.fetch('id')}:#{row.fetch('rep')}"]

  def passes
    rows.group_by { |row| row.fetch("rep") }.sort.map do |rep, group|
      judged = group.filter_map { |r| judgment(r) }
      { "rep" => rep,
        "state_failure" => group.count { |r| checks(r).value?(false) }.fdiv(group.size),
        "exchange_failure" => group.count { |r| r["error"] || r["fallback"] || r.fetch("calls").any? { |c| c["error"] } }.fdiv(group.size),
        "contradiction" => judged.size == group.size ? judged.count { |j| j.fetch("contradiction") }.fdiv(group.size) : nil,
        "reaction_words" => group.sum { |r| words((r["reaction"] || {}).values.join(" ")) }.fdiv(group.size),
        "narration_words" => group.sum { |r| words(r["narration"]) }.fdiv(group.size),
        "judged" => judged.size, "cases" => group.size }
    end
  end

  def board
    { model: data.fetch("model"), corpus_digest: data.fetch("corpus_digest"), passes: passes,
      checks: rows.map { |r| { id: r.fetch("id"), rep: r.fetch("rep"), checks: checks(r), human: judgment(r) } },
      registry_usage_usd: rows.sum { |r| r.fetch("calls").sum { |c| c["registry_cost_usd"].to_f } },
      provider_reported_partial_usd: rows.sum { |r| r.fetch("calls").sum { |c| c["provider_cost_usd"].to_f } },
      limits: "Voice, memory fidelity, long-term behavior and personality are unmeasured. Missing human annotations are unavailable, never clean." }
  end

  def compare(other)
    raise ArgumentError, "different corpus or model" unless data.values_at("corpus_digest", "model") == other.data.values_at("corpus_digest", "model")
    [ self, other ].each(&:validate_complete!)
    METRICS.to_h do |metric|
      left = passes.map { |p| p[metric] }
      right = other.passes.map { |p| p[metric] }
      [ metric, left.include?(nil) || right.include?(nil) ? { outcome: "unavailable" } : Eval::Noise.compare(metric, left, right).to_h ]
    end
  end

  def validate_complete!
    expected_ids = Eval::Dialogue.cases.map { |k| k.fetch("id") }.sort
    raise ArgumentError, "incomplete repetitions" unless rows.map { |r| r.fetch("rep") }.uniq.sort == (1..data.fetch("reps")).to_a
    rows.group_by { |r| r.fetch("rep") }.each_value do |group|
      raise ArgumentError, "incomplete or duplicated cases" unless group.map { |r| r.fetch("id") }.sort == expected_ids
    end
  end

  private

  def words(text) = text.to_s.scan(/[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*/u).size

  def validate_annotations!
    annotations.each do |key, entry|
      row = rows.find { |r| "#{r.fetch('id')}:#{r.fetch('rep')}" == key }
      raise ArgumentError, "annotation has unknown row #{key}" unless row
      raise ArgumentError, "annotation needs a boolean and reason" unless [ true, false ].include?(entry["contradiction"]) && entry["reason"].present?
      raise ArgumentError, "annotation is for different prose" unless entry["narration_digest"] == Digest::SHA256.hexdigest(row["narration"].to_s)
      next unless entry["contradiction"]
      raise ArgumentError, "positive annotation needs a displayed excerpt" unless entry["excerpt"].present? && row["narration"].to_s.include?(entry["excerpt"])
    end
  end
end
