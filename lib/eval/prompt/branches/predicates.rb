# Bounded explicit-claim predicates, not a semantic truthfulness judge.
# Absence of a matching phrase is silence, never proof of fidelity. Negated,
# hypothetical and quoted claims are left to human truthfulness labels. Exact
# future-summary leakage is detectable; paraphrases and natural quest fit are
# human-only. Precision/recall examples live in branches_predicates_test.rb.
module Eval::Prompt::Branches::Predicates
  extend self

  CHECKS = {
    blow_contradicted: "explicit blow numbers, participants, misses or invented combat mechanics",
    toll_contradicted: "explicit toll damage or a wound despite a recorded save",
    throw_contradicted: "explicit thrown object, target or result contradicts the recorded throw",
    body_contradicted: "explicit remaining hit points or life/death contradicts a placed body",
    beat_contradicted: "literal future-summary leak or explicit denial of the next beat"
  }.freeze

  def judgeable?(code, facts)
    case code.to_sym
    when :blow_contradicted then Array(facts["blows"]).any?
    when :toll_contradicted then Array(facts["tolls"]).any?
    when :throw_contradicted then facts["throw"].present?
    when :body_contradicted then Array(facts["bodies"]).any?
    when :beat_contradicted then facts["next_beat"].present?
    else false
    end
  end

  def claims(code, text, facts)
    return [] unless judgeable?(code, facts)

    Story::Audit::Prose.sentences(text).select do |sentence|
      # These grammars intentionally abstain on uncertain attribution.
      next false if sentence.match?(/["“”]|\b(?:if|could|might|would|not|never|no longer)\b/i)

      public_send(code, sentence, facts)
    end
  end

  def body_name(body)
    body["player"] ? "(?:you|your)" : person(body["name"])
  end

  def person(name)
    "(?:#{Regexp.escape(name)}|#{Regexp.escape(name.split.first)})"
  end

  def actor(name, facts)
    body = Array(facts["bodies"]).find { |row| row["name"] == name }
    body ? body_name(body) : person(name)
  end

  def blow_contradicted(sentence, facts)
    blows = facts.fetch("blows")
    return true if sentence.match?(/\b(?:roll(?:s|ed)? (?:for )?initiative|wins? initiative|to-hit roll|armou?r (?:absorbs?|blocks?|reduces?))\b/i)

    blows.any? do |blow|
      attacker = actor(blow.fetch("attacker"), facts)
      target = actor(blow.fetch("target"), facts)
      explicit = sentence.match(/\b#{attacker}\s+(?:hit|hits|struck|strike|strikes)\s+#{target}\s+for\s+(\d+)\s+(?:hit points?|damage)\b/i)
      wrong_damage = explicit && explicit[1].to_i != blow.fetch("damage")
      missed = sentence.match?(/\b#{attacker}(?:'s)?\s+(?:(?:blow|attack|strike)\s+)?miss(?:es|ed)?\b/i)
      die = sentence.match(/\b#{attacker}(?:'s)?\s+(?:blow|attack|strike)\s+(?:uses?|rolls?)\s+(\d+)d(\d+)\b/i)
      wrong_die = die && (die[1].to_i != 1 || die[2].to_i != blow.fetch("die"))
      named = sentence.match(/\b#{attacker}\s+(?:hit|hits|struck|strike|strikes)\s+(.+?)\s+for\s+\d+\s+(?:hit points?|damage)\b/i)
      wrong_target = named && !named[1].match?(/\A#{target}\z/i)
      wrong_damage || missed || wrong_die || wrong_target
    end
  end

  def toll_contradicted(sentence, facts)
    facts.fetch("tolls").any? do |toll|
      target = actor(toll.fetch("name"), facts)
      lost = sentence.match(/\b#{target}\s+lose?s?\s+(\d+)\s+hit points?\b/i)
      cost = sentence.match(/\b#{Regexp.escape(toll.fetch("where"))}\s+costs?\s+#{target}\s+(\d+)\s+hit points?\b/i)
      amount = lost || cost
      (amount && amount[1].to_i != toll.fetch("damage")) ||
        (toll.fetch("saved") && sentence.match?(/\b#{target}\s+(?:are|is)\s+(?:wounded|hurt|injured)\b/i))
    end
  end

  def throw_contradicted(sentence, facts)
    thrown = facts.fetch("throw")
    item = Regexp.escape(thrown.fetch("item"))
    target = actor(thrown.fetch("target"), facts)
    claim = sentence.match(/\byou\s+(?:throw|threw|hurl|hurled)\s+(?:the\s+)?(.+?)\s+at\s+(.+?)(?:[,.!;]|$)/i)
    wrong_pair = claim && (!claim[1].match?(/\A#{item}\z/i) || !claim[2].match?(/\A#{target}\z/i))
    wrong_pair || sentence.match?(/\b(?:the\s+)?#{item}\s+(?:misses|missed|stays in your hands|remains in your hands)\b/i)
  end

  def body_contradicted(sentence, facts)
    facts.fetch("bodies").any? do |body|
      name = body_name(body)
      status = sentence.match(/\b#{name}\s+(?:are|is|remain|remains)\s+(alive|dead|unhurt)\b/i)
      wrong_status = status && status_contradicted?(status[1].downcase, body)
      hp = sentence.match(/\b#{name}\s+(?:have|has)\s+(\d+)\s+hit points?\s+(?:left|remaining)\b/i)
      fraction = sentence.match(/\b#{name}\s+(?:have|has)\s+(\d+)\s+of\s+(\d+)\s+hit points?\b/i)
      wrong_status || (hp && hp[1].to_i != body.fetch("hp")) ||
        (fraction && [ fraction[1].to_i, fraction[2].to_i ] != body.values_at("hp", "max"))
    end
  end

  def beat_contradicted(sentence, facts)
    leak = Array(facts["withheld"]).any? { |summary| sentence.downcase.include?(summary.downcase.delete_suffix(".")) }
    next_beat = facts.fetch("next_beat").delete_suffix(".")
    leak || sentence.match?(/\byou must abandon (?:the task to )?#{Regexp.escape(next_beat)}\b/i)
  end

  private

  def status_contradicted?(word, body)
    case word
    when "dead" then body.fetch("hp").positive?
    when "alive" then body.fetch("hp").zero?
    when "unhurt" then body.fetch("hp") < body.fetch("max")
    else false
    end
  end
end
