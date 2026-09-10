# Bounded signals, never a semantic quality score. First-person letters and
# second-person notices are legitimate inscriptions, so pronouns alone are NOT
# narration flags. Only opening reader-action and explicit framing phrases are
# flagged. Fictional quotations of those phrases can be false positives; other
# descriptive paraphrases can be missed. Human fit remains unjudged by code.
#
# Sentence punctuation is meaningful for prose, not labels, dates or tallies.
# Apply the existing truncated_prose predicate only to sentence-like last lines
# (an explicit finite-verb cue). Other endings remain unjudgeable, not passes.
# This sacrifices recall rather than declaring every unpunctuated sign broken.
class Eval::Inscription::Scorer
  CHECKS = %w[failed empty truncated_prose narration_framing length_bound description_repeated].freeze
  FRAME = /\A\s*["“]?(?:you\s+(?:read|see|notice|unfold|turn|find)\b|(?:the\s+)?(?:inscription|text|note|sign|label)\s+(?:says|reads)\b|(?:written|inscribed)\s+on\b)/i
  SENTENCE = /\b(?:is|are|was|were|has|have|had|will|shall|must|cannot|should)\b/i

  def self.text(row)
    raw = row["raw"]
    raw = JSON.parse(raw) if raw.is_a?(String)
    raw.is_a?(Hash) ? raw["inscription"] : nil
  rescue JSON::ParserError
    nil
  end

  def self.checks(row)
    words = text(row)
    return CHECKS.to_h { |check| [ check, check == "failed" ? row["error"].present? : nil ] } if words.nil?

    last = words.to_s.lines.last.to_s
    { "failed" => row["error"].present?, "empty" => words.to_s.strip.empty?,
      "truncated_prose" => last.match?(SENTENCE) ? Story::Audit::Prose.truncated?(last) : nil,
      "narration_framing" => words.to_s.match?(FRAME),
      "length_bound" => words.to_s.length > Item::INSCRIPTION_LIMIT,
      "description_repeated" => row["description"].present? && words.to_s.include?(row.fetch("description")) }
  end

  def self.rates(rows, check)
    rows.group_by { |row| row.fetch("rep") }.sort.map do |_rep, readings|
      values = readings.map { |row| checks(row).fetch(check) }.compact
      values.empty? ? nil : values.count(true).fdiv(values.size)
    end
  end
end
