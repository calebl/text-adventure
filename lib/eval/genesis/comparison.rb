# Compare rates over repetitions, with the same noise verdict as every bench.
# The corpus must match; request bytes may differ because prompts are the
# treatment. Report each producer separately as well as the whole fixed corpus.
class Eval::Genesis::Comparison
  def initialize(before, after)
    @before, @after = before, after
    raise ArgumentError, "genesis corpora differ" unless before.corpus_digest == after.corpus_digest
    raise ArgumentError, "genesis arms differ" unless before.arms == after.arms
    [ before, after ].each do |result|
      raise ArgumentError, "unstable requests" unless result.document["request_stable"]
      expected = result.request_digests.flat_map { |id, calls| calls.keys.map { |call| [ id, call ] } }.sort
      unless result.passes.size == result.reps && result.passes.all? { |pass|
        pass.fetch("readings").map { |row| [ row["id"], row["call"] ] }.sort == expected
      }
        raise ArgumentError, "incomplete genesis set"
      end
      answered = result.rows.filter_map { |row| row["answered_by"] }.uniq
      unless answered.all? { |model| result.arms.map { |arm| Eval::Classifier::Arm.parse(arm).model }.include?(model) }
        raise ArgumentError, "genesis pinning failed"
      end
    end
  end

  def lines
    calls = [ nil ] + (@before.rows + @after.rows).map { |row| row["call"] }.uniq.sort
    calls.flat_map do |call|
      [ "#{call || 'All genesis'}:" ] + (Eval::Genesis::Scorer::CHECKS.keys + [ :failures ]).map do |code|
        left, right = [ @before, @after ].map { |result| result.values(code, call: call) }
        if left.compact.empty? || right.compact.empty?
          "#{code}: unavailable"
        else
          "#{code}: #{Eval::Noise.compare(code, left, right).headline}"
        end
      end
    end
  end
end
