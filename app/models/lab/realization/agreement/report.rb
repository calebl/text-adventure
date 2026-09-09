# `rake eval:realization_alignment`, PRINTED.
#
# `Lab::Realization::Agreement` is the instrument and its header is the design;
# what belongs here is what a reader is shown and in what order. Offline, free,
# no key and no model call: every figure is read off samples already bought.
#
# WHAT IT PRINTS, AND WHY EACH IS APART FROM THE OTHERS -- the shape
# `Eval::Realization::Report` established:
#
#   THE HEADING          what an eligible verdict is, in the words a reader
#                        needs before the first number means anything, and the
#                        threshold below which no percentage is printed.
#   ONE SET AT A TIME    tuning, then held out. Two sets, never pooled, each
#                        crossing the threshold on its own verdicts or not at
#                        all. A set with nothing in it says so and prints no
#                        table.
#   THE CHECKS           in `Eval::Realization::Scorer::CHECKS`' trust order,
#                        each with BOTH denominators -- judgeable, and of those
#                        eligible -- and the verdicts it fired on. Unavailable
#                        where nothing gave it anything to read, never nought.
#   THE SUSPECTS         a check that fired on a sample he called `good`, with
#                        the sample's id and its path, because the point of the
#                        figure is to open the disagreement.
#   THE MISSES           a sample he called `weak` or `bad` that no check
#                        caught. The next check to write.
#   THE PROSE            his prose verdicts as their own tally, stated as not
#                        scored and not scoreable.
class Lab::Realization::Agreement::Report
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
    say "THE AGREEMENT -- the realization checks against the captain's own verdicts"
    say "Offline and free: every figure below is read off samples already bought."
    say
    say "AN ELIGIBLE VERDICT IS ONE THAT SPEAKS TO THE CHECK. A sample called `good`"
    say "speaks to every check that was judgeable on it; a `weak` or a `bad` speaks only"
    say "to the checks the aspects he ticked name, so a room faulted for its prose says"
    say "nothing about its exits and is in no exit check's denominator."
    say "Below #{Story::Scoreboard::MIN_VERDICTS} eligible verdicts the counts are printed and no percentage is."
    say "Tuning and held out are two sets and are never pooled."
    say RULE
  end

  def board(set)
    say
    say "SET  #{set.label}#{held_out_note(set)}"

    if set.drawn.zero?
      say "  (nothing drawn in #{set.label == Lab::Realization::Agreement::HELD_OUT ? "the held-out world" : "these worlds"} yet)"
      return
    end

    say "  #{set.drawn} sample#{"s" unless set.drawn == 1}, #{set.judged.size} judged, " \
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
    return "" unless set.label == Lab::Realization::Agreement::HELD_OUT

    "   [#{Eval::HELD_OUT} -- reported apart, never pooled with the tuning worlds]"
  end

  def tally(set)
    return "none yet" if set.verdicts.empty?

    Lab::Realization::Sample::VERDICTS.map { |word| "#{word} #{set.verdicts[word].to_i}" }.join(", ")
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
      return "unavailable -- nothing drawn gave the check anything to read"
    end
    unless reading.judged?
      return "no eligible verdict yet (#{reading.judgeable} judgeable, none of them judged on this)"
    end

    figure = reading.established? ? "#{reading.fraction} (#{reading.percentage}%)" :
                                    "#{reading.fraction} -- not established"
    format("%-28s fired on good %d, weak %d, bad %d   [%d judgeable]",
           figure, reading.on_good, reading.on_weak, reading.on_bad, reading.judgeable)
  end

  def suspects(set)
    found = set.suspects
    say "  SUSPECTS -- a check that fired on a sample he called good"
    return say("    (none)") if found.empty?

    found.each { |suspect| say "    #{where(suspect.sample)}  #{suspect.code}" }
  end

  def missed(set)
    found = set.missed
    say "  MISSED -- a sample he called weak or bad that no check fired on"
    return say("    (none)") if found.empty?

    found.each do |sample|
      aspects = sample.aspect_names.any? ? sample.aspect_names.join(", ") : "no aspect ticked"
      say "    #{where(sample)}  #{sample.verdict} -- #{aspects}"
    end
  end

  # A SAMPLE HE CAN OPEN. The id alone is not enough to inspect a disagreement
  # with; the page beside it carries the prompt as sent, which is the only thing
  # that tells a wrong check from a right one.
  def where(sample)
    "sample ##{sample.id} #{Rails.application.routes.url_helpers.lab_sample_path(sample)} " \
      "(#{sample.kind.name} in #{sample.kind.world})"
  end

  def prose(set)
    say "  PROSE -- kept, reported, never scored"
    say "    #{set.prose_verdicts} of #{set.judged.size} judged sample#{"s" unless set.judged.size == 1} " \
        "were faulted for their prose."
    say "    No check reads prose and none is going to -- see"
    say "    Eval::Realization::UNAVAILABLE_TO_A_REALIZATION. This is ground truth for a check"
    say "    that does not exist, and it is not an agreement figure."
  end

  def closing
    say
    say RULE
    say "A figure here is about the CHECKS and not about the prompt: it says whether a"
    say "check agrees with him, not whether the generator is picking what he wants. That"
    say "second question is the hit rate, per kind, at /lab/kinds."
    say RULE
  end

  def say(line = "") = io.puts(line)
end
