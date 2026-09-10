# Lexical readings, NOT a semantic judge. Each field has its own denominator.
# Fact-missing strict/inclusive are word-cue proxies for the study rubric:
# body needs Maren plus death language in one sentence; inclusive also accepts
# motionless/slumped/stillness (which may mean unconsciousness). Wound needs
# Maren plus injury language; key needs brass key plus possession language;
# toll needs pain/injury/HP plus water/stairs/crossing language; floor needs the
# ledger plus a surface/location word. Co-occurrence does not prove attribution,
# negation, ownership or causation; paraphrases may be missed. These proxies
# never claim absence of semantic contradiction. Precision evidence is replayed
# against the retained annotations in ScorerTest; synthetic cases pin misses.
#
# Second-person is a you/your cue; past-tense is a narrow you-was/were/felt/saw
# cue, NOT a full tense parser (a flashback can trigger it). Summary third-person
# is a named-player/player/he/she/they cue with no you/your/I/we, not a syntactic
# proof. Sentence count uses the existing splitter and can mistake abbreviations
# or dialogue for boundaries. Revisit is merely back/again/return/familiar, not
# recognition quality. All are printed as lexical proxies, never prose quality.
# Existing Prompt predicates retain their documented precision limits. Arrival
# departure is unavailable after a move; third-person-protagonist is deliberately
# not applied to summary, where that person is REQUIRED by Scene::Schema.
class Eval::Arrival::Scorer
  GENERIC = %w[unrecorded_departure unrecorded_arrival item_not_held truncated_prose third_person_protagonist].freeze
  CUES = {
    "body" => [ /\bMaren\b/i, /\b(dead|death|corpse|lifeless)\b/i, /\b(motionless|slumped|stillness)\b/i ],
    "wound" => [ /\bMaren\b/i, /\b(hurt|wound\w*|injur\w*|bleed\w*|pain)\b/i, /\b(limp\w*|winc\w*)\b/i ],
    "key" => [ /\bbrass key\b/i, /\b(carry\w*|carrie[ds]|hold\w*|held|palm|pocket|your hand|possession)\b/i, /\byour\b/i ],
    "toll" => [ /\b(water|wet|stair\w*|cross\w*|way from|flood\w*)\b/i, /\b(hurt|wound\w*|injur\w*|pain\w*|hit points?|HP)\b/i, /\b(ache\w*|sting\w*)\b/i ],
    "floor" => [ /\bblue ledger\b/i, /\b(lies|lying|floor|desk|here)\b/i, /\b(near|beside)\b/i ]
  }.freeze

  def self.fact_missing?(text, fact, inclusive: false)
    subject, strict, implied = CUES.fetch(fact)
    !Story::Audit::Prose.sentences(text).any? do |sentence|
      sentence.match?(subject) && (sentence.match?(strict) || (inclusive && sentence.match?(implied)))
    end
  end

  def self.read(row)
    readings = {}
    %w[description summary].each do |field|
      text = row[field].to_s
      checks = { "unusable" => row["error"].present? || text.blank? }
      if !checks["unusable"]
        generic = Eval::Prompt::Scorer.new([ row.merge("text" => text, "act" => "move") ])
        GENERIC.each do |code|
          unavailable = (field == "summary" && code == "third_person_protagonist") ||
            (code == "unrecorded_departure" && row.dig("facts", "moved")) || generic.judgeable_for(code).zero?
          checks[code] = unavailable ? nil : generic.flagged_for(code).any?
        end
        count = Story::Audit::Prose.sentences(text).size
        checks["sentence_count_outside_schema"] = field == "summary" ? count != 1 : !(3..5).cover?(count)
        if field == "description"
          checks["second_person_cue_missing"] = !text.match?(/\b(you|your)\b/i)
          checks["past_tense_cue"] = text.match?(/\byou (were|was|felt|saw|had|entered)\b/i)
          checks["multiple_paragraphs"] = text.match?(/\n\s*\n/)
          checks["revisit_cue_missing"] = row.dig("facts", "returning") ? !text.match?(/\b(back|again|return\w*|familiar)\b/i) : nil
        else
          checks["third_person_cue_missing"] = text.match?(/\b(you|your|I|we|our)\b/i) ||
            !text.match?(/\b(Iri|Calder|player|he|she|they)\b/i)
        end
      end
      required = row.fetch("facts").fetch("required")
      %w[strict inclusive].each do |mode|
        checks["fact_missing_#{mode}"] = if required.empty?
          nil
        else
          checks["unusable"] || required.any? { |fact| fact_missing?(text, fact, inclusive: mode == "inclusive") }
        end
      end
      readings[field] = checks
    end
    readings
  end
end
