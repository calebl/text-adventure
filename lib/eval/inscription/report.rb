# Stored answers are the replay surface; annotations are deliberately nullable.
# A future lab can write human_fit/human_note per reading without buying a call.
# The board exposes those fields but supplies no verdict on world/register fit.
module Eval::Inscription::Report
  extend self

  def load_set(name)
    JSON.parse(File.read(Eval.set_path(name).join(Eval::Inscription::RESULTS)))
  end

  def groups(data)
    data.fetch("rows").group_by { |row| row.fetch("story") == Eval::HELD_OUT ? "held-out" : "tuning" }
  end

  def complete?(data)
    ids = data.fetch("case_identities").keys.sort
    reps = data.fetch("rows").group_by { |row| row.fetch("rep") }
    reps.keys.sort == (1..data.fetch("reps")).to_a &&
      reps.values.all? { |rows| rows.map { |row| row.fetch("id") }.sort == ids }
  end

  def board(data)
    lines = [ "Inscription: #{data.fetch('model')}; #{Eval::RequestIdentity.label(data['request_identity'])}",
              format("Receipted cost (cached input priced conservatively): $%.6f", data.fetch("rows").sum { |row| row.fetch("dollars") }) ]
    lines << "INCOMPLETE: missing or duplicate readings; comparison is unavailable" unless complete?(data)
    groups(data).each do |group, rows|
      lines << "#{group}:"
      Eval::Inscription::Scorer::CHECKS.each do |check|
        values = Eval::Inscription::Scorer.rates(rows, check)
        lines << "  #{check}: #{values.map { |value| value.nil? ? 'unavailable' : format('%.3f', value) }.join(' / ')} (rates per rep)"
      end
    end
    lines << "Fit/register/meaning are human judgements. Unavailable punctuation is not a clean finish."
    data.fetch("rows").each do |row|
      lines << "#{row.fetch('id')} rep #{row.fetch('rep')}: human_fit=#{row['human_fit'] || 'unjudged'}; human_note=#{row['human_note'].inspect}"
      lines << "  #{Eval::Inscription::Scorer.text(row).inspect}"
    end
    lines
  end

  def compare(before, after)
    raise ArgumentError, "incomplete set" unless complete?(before) && complete?(after)

    %w[corpus_digest model].each do |key|
      raise ArgumentError, "incomparable #{key}" unless before.fetch(key) == after.fetch(key)
    end
    lines = [ "Request identity changed: #{before.fetch('request_identity') != after.fetch('request_identity')}" ]
    groups(before).each do |group, rows|
      right = groups(after).fetch(group)
      Eval::Inscription::Scorer::CHECKS.each do |check|
        left_rates = Eval::Inscription::Scorer.rates(rows, check)
        right_rates = Eval::Inscription::Scorer.rates(right, check)
        verdict = Eval::Noise.compare(check, left_rates, right_rates)
        lines << "#{group} #{check}: #{verdict.headline}"
      end
    end
    lines
  end
end
