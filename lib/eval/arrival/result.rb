# Stored responses are scored offline. Study annotations remain attached only
# to the exact study text: they are never transferred to newly bought prose.
# ANNOTATIONS may supply a new reader's labels keyed by response_identity; a
# digest over both fields prevents silently attaching them after prose edits.
class Eval::Arrival::Result
  attr_reader :data, :annotations

  def initialize(data, annotations: {})
    @data = data
    @annotations = annotations
    validate_annotations!
  end

  def self.load(path, **options) = new(JSON.parse(Pathname.new(path).join(Eval::Arrival::RESULTS).read), **options)
  def rows = data.fetch("rows")
  def self.response_identity(row) = Digest::SHA256.hexdigest(JSON.generate(row.values_at("id", "description", "summary")))

  def counts(selected)
    selected.each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, metrics|
      Eval::Arrival::Scorer.read(row).each do |field, checks|
        checks.each { |code, value| metrics["#{field}.#{code}"] << (value ? 1.0 : 0.0) unless value.nil? }
      end
    end.transform_values { |values| { flagged: values.sum.to_i, judgeable: values.size } }
  end

  def figures(selected)
    counts(selected).transform_values { |count| count.fetch(:flagged).fdiv(count.fetch(:judgeable)) }
  end

  def board
    lines = [ "Arrival lexical proxies; not semantic correctness or prose quality.",
      "Model: #{data.fetch('model')}; corpus: #{data.fetch('corpus_digest')}",
      "Description and summary scored separately; unavailable checks have no denominator." ]
    rows.group_by { |r| r.fetch("rep") }.each do |rep, selected|
      lines << "rep #{rep}: #{counts(selected).to_json}"
    end
    rows.each do |row|
      human = annotations[self.class.response_identity(row)]
      lines << "#{row.fetch('id')}:#{row.fetch('rep')} request=#{Eval::RequestIdentity.label(row["request_identity"])} response_identity=#{self.class.response_identity(row)} #{Eval::Arrival::Scorer.read(row).to_json}"
      lines << "  annotation: #{human ? human.to_json : 'unavailable (this response has no annotation)'}"
    end
    if data["budget"]
      entries = data.fetch("budget").fetch("entries")
      lines << "All attempts (including superseded fixture readings): #{entries.size}; " \
        "accounted USD: #{entries.sum { |e| e.fetch('accounted_micros') } / 1_000_000.0}; " \
        "provider USD: #{entries.sum { |e| e.dig('receipt', 'provider_cost_usd').to_f }}"
    end
    lines
  end

  def compare(other)
    raise ArgumentError, "different corpora" unless data.fetch("corpus_digest") == other.data.fetch("corpus_digest")
    raise ArgumentError, "different models" unless data.fetch("model") == other.data.fetch("model")
    [ self, other ].each do |result|
      expected = Eval::Arrival.cases.map { |k| k.fetch("id") }.sort
      groups = result.rows.group_by { |r| r.fetch("rep") }
      raise ArgumentError, "incomplete repetitions" unless groups.size >= Eval::Noise::MIN_RUNS &&
        groups.values.all? { |rs| rs.map { |r| r.fetch("id") }.sort == expected }
    end
    sides = [ self, other ].map { |result| result.rows.group_by { |r| r.fetch("rep") }.values.map { |rs| result.figures(rs) } }
    metrics = sides.flat_map { |passes| passes.flat_map(&:keys) }.uniq
    metrics.map do |metric|
      values = sides.map { |passes| passes.filter_map { |pass| pass[metric] } }
      { metric: metric, **Eval::Noise.compare(metric, *values).to_h }
    end
  end

  def validate_annotations!
    known = rows.map { |row| self.class.response_identity(row) }
    raise ArgumentError, "annotations contain unknown response identities" unless (annotations.keys - known).empty?
    annotations.each_value do |annotation|
      %w[description summary].each do |field|
        reading = annotation.fetch(field)
        %w[contradiction required_fact_acknowledged].each do |metric|
          raise ArgumentError, "annotation must preserve true/false/null" unless [ true, false, nil ].include?(reading.fetch(metric))
        end
        raise ArgumentError, "annotation needs a reason" if reading["reason"].blank?
        if reading["contradiction"] == true || reading["required_fact_acknowledged"] == true
          raise ArgumentError, "positive annotation needs a supporting quote" if reading["supporting_quote"].blank?
        end
      end
    end
  end

  def self.study_board
    key = JSON.parse(Eval::Arrival::STUDY.join("arrival-reading-key.json").read)
    independent = JSON.parse(Eval::Arrival::STUDY.join("arrival-independent-annotations.json").read).fetch("annotations").index_by { |r| r.fetch("id") }
    root = JSON.parse(Eval::Arrival::STUDY.join("arrival-root-annotations.json").read).fetch("readings")
    lines = [ "HISTORICAL STUDY annotations, not labels for the standing set:" ]
    %w[before after].each do |arm|
      JSON.parse(Eval::Arrival::STUDY.join("arrival-#{arm}.json").read).fetch("rows").each do |row|
        id = key.find { |_id, identity| identity == { "arm" => arm, "case" => row.fetch("case"), "rep" => row.fetch("rep") } }&.first
        raise "study annotation identity missing" unless id
        kase = Eval::Arrival.cases.find { |k| k["id"] == row["case"] }
        proxies = %w[description summary].to_h do |field|
          [ field, %w[strict inclusive].to_h { |mode| [ mode, kase.fetch("facts").any? { |fact| Eval::Arrival::Scorer.fact_missing?(row.fetch(field), fact, inclusive: mode == "inclusive") } ] } ]
        end
        lines << "#{arm}/#{row['case']}/#{row['rep']} proxies=#{proxies.to_json} independent=#{independent.fetch(id).to_json} root=#{root.fetch(id).to_json}"
      end
    end
    lines
  end
end
