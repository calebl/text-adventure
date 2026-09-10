# `rake eval:exits_alignment`, offline and free. Agreement's header owns the
# attribution rules. This prints the realization twin's two denominators and
# refusal, with names beside the sample paths so each disagreement can be opened.
# Held out stays labelled and apart; prose remains its own tally.
class Lab::Exits::Agreement::Report
  RULE = ("-" * 78).freeze

  attr_reader :sets, :io

  def initialize(sets, io: $stdout)
    @sets = Array(sets)
    @io = io
  end

  def print
    heading
    sets.each { |set| board(set) }
    closing
  end

  private

  def heading
    say RULE
    say "THE AGREEMENT -- the exits checks against the captain's own verdicts"
    say "Offline and free: every figure below is read off samples already bought."
    say
    say "AN ELIGIBLE VERDICT speaks to a check on a named place, counted once across"
    say "its draws. Good speaks to every judgeable per-name check; weak/bad speaks"
    say "through its aspects. shouldnt_exist speaks to every per-name check."
    say "Whole-answer and detail checks are unavailable to a name judgement."
    say "Below #{Story::Scoreboard::MIN_VERDICTS} eligible verdicts the counts are printed and no percentage is."
    say "Tuning and held out are two sets and are never pooled."
    say RULE
  end

  def board(set)
    say
    say "SET  #{set.label}#{held_out_note(set)}"

    if set.drawn.zero?
      say "  (nothing drawn in #{set.label == Lab::Exits::Agreement::HELD_OUT ? "the held-out world" : "these worlds"} yet)"
      return
    end

    say "  #{set.drawn} sample#{"s" unless set.drawn == 1}, #{set.judged.size} names judged, " \
        "#{set.unjudged} unjudged, #{set.failed} failed"
    say "  verdicts: #{tally(set)}"
    say
    checks(set)
    say
    suspects(set)
    say
    missed(set)
    say
    prose(set)
  end

  def held_out_note(set)
    return "" unless set.label == Lab::Exits::Agreement::HELD_OUT

    "   [#{Eval::HELD_OUT} -- reported apart, never pooled with the tuning worlds]"
  end

  def tally(set)
    return "none yet" if set.verdicts.empty?

    Lab::Exits::Judgement::VERDICTS.map { |word| "#{word} #{set.verdicts[word].to_i}" }.join(", ")
  end

  # THE TABLE. Both denominators on every row, because "the check could not be
  # read here" and "nothing he said speaks to it" are different states and a
  # single number would hide which one a reader is looking at.
  def checks(set)
    say "  THE CHECKS -- agreed of eligible verdicts, with what the check fired on"
    set.readings.each do |reading|
      say format("  %-38s %s", reading.code, verdict_line(reading))
      say format("  %-38s   %s%s", "", reading.description, reading.keyword? ? "  [KEYWORD]" : "")
    end
  end

  def verdict_line(reading)
    unless reading.available?
      return "unavailable -- no attributable evidence (0 judgeable, 0 eligible)"
    end
    unless reading.judged?
      return "no eligible verdict yet (#{reading.judgeable} judgeable, 0 eligible)"
    end

    figure = reading.established? ? "#{reading.fraction} (#{reading.percentage}%)" :
                                    "#{reading.fraction} -- not established"
    format("%-28s fired on good %d, weak %d, bad %d   [%d judgeable]",
           figure, reading.on_good, reading.on_weak, reading.on_bad, reading.judgeable)
  end

  def suspects(set)
    found = set.suspects
    say "  SUSPECTS -- a check that fired on a name he called good"
    return say("    (none)") if found.empty?

    found.each { |suspect| say "    #{where(suspect.sample)}  #{suspect.name} -- #{suspect.code}" }
  end

  def missed(set)
    found = set.missed
    say "  MISSED -- a name he called weak or bad that no attributable check fired on"
    return say("    (none)") if found.empty?

    found.each do |sample|
      aspects = sample.aspect_names.any? ? sample.aspect_names.join(", ") : "no aspect ticked"
      say "    #{where(sample.sample)}  #{sample.name} -- #{sample.verdict} -- #{aspects}"
    end
  end

  # A SAMPLE HE CAN OPEN. The id alone is not enough to inspect a disagreement
  # with; the page beside it carries the prompt as sent, which is the only thing
  # that tells a wrong check from a right one.
  def where(sample)
    "sample ##{sample.id} #{Rails.application.routes.url_helpers.lab_exits_sample_path(sample)} " \
      "(#{sample.vantage.name} in #{sample.vantage.world})"
  end

  def prose(set)
    say "  PROSE -- kept, reported, never scored"
    say "    #{set.prose_verdicts} of #{set.judged.size} judged name#{"s" unless set.judged.size == 1} " \
        "were faulted for teaser or name prose."
    say "    No check reads prose and none is going to -- see"
    say "    Eval::Realization::UNAVAILABLE_TO_A_REALIZATION. This is ground truth for a check"
    say "    that does not exist, and it is not an agreement figure."
  end

  def closing
    say
    say RULE
    say "A figure here is about the CHECKS and not about the prompt: it says whether a"
    say "check agrees with him, not whether the generator is picking what he wants. That"
    say "second question is the hit rate, per vantage, at /lab/exits."
    say RULE
  end

  def say(line = "") = io.puts(line)
end
