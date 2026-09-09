# A SCORED VANTAGE, WRITTEN OUT AS A CORPUS CASE FOR A PERSON TO COMMIT.
#
# THE CAPTAIN'S CALL 6 OF 2026-09-08, answered (a): *extend the existing
# realization corpus; widen `expects_inside` from boolean to quantifier.* And
# the half of his ask this file is, verbatim: *"I can run through a set of
# samples, score them and then we can use that to create alignment and then
# **maintain alignment in the future**."* The exits lab creates the alignment --
# a vantage, a quantifier, a rate. Maintaining it means the same vantage being
# re-run against a changed prompt, and only `Eval::Realization`'s corpus can do
# that. This is the one step between the two.
#
# IT IS `Lab::Realization::Promotion` WITH A DIFFERENT SUBJECT, and every rule
# that file argues for holds here unchanged: it EMITS TEXT AND WRITES NOTHING,
# because `test/fixtures/files/realization_corpus.yml` is a checked-in
# measurement input and committing a case moves `Eval::Realization.digest`,
# which fails `Eval::Realization::KeptSetTest` until a new baseline is bought.
# That is a spend decision and therefore a person's; a page that appended to the
# file itself could put the tree out of baseline as a side effect of somebody
# looking at it.
#
# WHAT IT CARRIES ACROSS, AND EVERY ONE OF THEM IS A MEASUREMENT INPUT:
#
#   story, room, teaser  the vantage's own facts. A name and a teaser are the
#                        ROOM's facts and not the world's, which is why they may
#                        live in the corpus at all.
#   reached_from         the way in, so the exits prompt's dead-end sentence is
#                        about the same place it was in the lab.
#   danger               required on a typed case, and for the sharpest reason
#                        in the corpus: the roll is keyed on the story's id and a
#                        staged copy is issued a new one on every load, so an
#                        undeclared danger would move the PROMPT digest between
#                        two runs of one tree.
#   absent               THE LOAD-BEARING INPUT, and the finding the lab was
#                        built on (`Lab::Exits`'s header, four bought draws): a
#                        vantage whose world still holds the places its model
#                        names has every `inside` pick discarded by
#                        `Location::Generator#connect_exit!`. A case promoted
#                        without the list measures a different question from the
#                        one he scored, so the list travels with it.
#   expects_inside       THE QUANTIFIER, which is the durable claim and the whole
#                        point of the promotion.
#
# AND WHAT IT MUST NOT CARRY: A PER-NAME EXPECTATION OR A PER-NAME JUDGEMENT.
# The captain took both shapes of per-name record in Call 4 (c) and they are
# LAB EVIDENCE, not bench labels. The reason is measured rather than tidy: 26 of
# 66 (case, name) pairs in the stored baseline appeared in exactly one of four
# repetitions, so a bench label keyed on a name a model chose is not a fact about
# the world -- it is a fact about what one model said one month, and it rots the
# first time the model names somewhere else. `Lab::Exits::Judgement`'s header
# carries the figure.
#
# SO THE PROMOTION HAS A SHAPE, AND IT IS WORTH SAYING PLAINLY: **the per-name
# judgements are the evidence, and the quantifier is the conclusion.** He judges
# the named places of a vantage across N draws; what he marked as *should be a
# building* is what the quantifier is written from; and the quantifier is what
# the corpus keeps. That is a promotion rather than a copy.
#
# THE VERDICTS ARE NOT CARRIED EITHER, on `Lab::Realization::Promotion`'s own
# argument: `Lab::Exits::Sample::ASPECTS` are the things no record can read --
# whether this is the right NUMBER of ways out, whether a dead end had a passage
# invented for it -- and `Eval::Realization::UNAVAILABLE_TO_A_REALIZATION` names
# the prose questions this bench refuses on purpose. They go in the `why` as
# provenance and no check reads them.
#
# AND THE BENCH WILL NOT REPORT THE LAB'S OWN RATE FOR THE SAME WORD. This is
# the one thing about a promoted case that would otherwise surprise whoever reads
# the board: `Lab::Exits::HitRate` scores the quantifier on `insides_given` in
# both directions, because a lab measures what the model SAID about a vantage he
# typed. `Eval::Realization::Scorer` scores the ceiling half on the insides that
# OPENED a place, because a bench measures what a game got and a discarded pick
# changed nothing. Two questions, one word, and neither is the other's
# approximation -- that scorer's own header has the split.
class Lab::Exits::Promotion
  # THE TWO YAML RULES, SHARED WITH `Lab::Realization::Promotion` rather than
  # written twice -- see `Lab::CaseYaml`.
  include Lab::CaseYaml

  # THE SHAPE A PROMOTED VANTAGE IS GROUPED UNDER, and its own rather than
  # `Lab::Realization::Promotion::SHAPE`. `Eval::Realization::Board` groups by
  # it, and the two labs promote genuinely different cases: a kind carries an
  # `inside` band and a `population` word a real exits call would have supplied,
  # and a vantage carries an `absent` list and no band at all. Filing both under
  # one word would put a case whose world was cut down beside one whose was not.
  #
  # IT IS A NEW SHAPE, WHICH MEANS A NEW DESIGNATED CASE, and this is the one
  # warning to carry into the PR that commits the first of them:
  # `Eval::Realization::Version` digests the prompts of the lowest-id case of
  # each shape, so the first `exits-promoted` case committed becomes one of them
  # and the PROMPT digest moves with it. That is correct -- such a case really
  # does send a prompt the corpus could not send before -- and it is said here
  # because it is the kind of movement a reader would otherwise credit to a
  # prompt edit nobody made.
  SHAPE = "exits-promoted".freeze

  # THE ID PREFIX, so a case's origin is legible in a board's leftmost column
  # without anybody reading the `why`.
  ID_PREFIX = "exits".freeze

  attr_reader :vantage, :samples

  def initialize(vantage, today: Date.current)
    @vantage = vantage
    @samples = vantage.samples.in_draw_order.to_a
    @today = today
  end

  def id = "#{ID_PREFIX}-#{vantage.name.parameterize}"

  def hit_rate = @hit_rate ||= Lab::Exits::HitRate.new(vantage, samples: samples)

  # WHETHER ANY DRAW ANSWERED THE ONE CALL THIS LAB MEASURES. A case may be
  # written from an unevidenced vantage -- the quantifier is his claim and not
  # the model's -- but the page and the task say so first, because a corpus case
  # that costs a re-baseline should not be the first time anybody notices that
  # nothing was drawn.
  def evidenced? = hit_rate.answered.any?

  # THE CASE AS YAML, ready to paste under `cases:`. Built by hand rather than
  # through `YAML.dump` because the comments are half of what a person reads --
  # which key had to be chosen, which record stayed in the lab, and what the
  # figures behind the `why` were.
  def to_yaml
    lines = [ "# Promoted out of the exits lab on #{@today.iso8601}. Read it, then commit it.",
              "- id: #{id}" ]
    lines.concat(fact_lines)
    lines.concat(expectation_lines)
    lines << "  shape: #{SHAPE}"
    lines.concat(why_lines)
    lines.concat(notes)
    "#{lines.join("\n")}\n"
  end

  # WHAT A PERSON HAS TO SETTLE OR KNOW BEFORE THE CASE IS WORTH COMMITTING, as
  # sentences. Empty only when the vantage hands over everything a case needs and
  # nothing about the set of draws behind it wants saying.
  def notes
    [ danger_note, quantifier_note, established_note, absent_note, per_name_note,
      population_note ].compact
  end

  private

  def fact_lines
    lines = [ "  story: #{scalar(vantage.world)}", "  room: #{scalar(vantage.name)}" ]
    lines.concat(folded("teaser", vantage.teaser))
    lines << "  reached_from: #{scalar(vantage.reached_from)}" if vantage.reached_from.present?
    lines << danger_line
    lines.concat(absent_lines)
    # A VANTAGE HE TYPED IS SOMEWHERE THE STORY POINTS INTO -- he typed it to see
    # what lies beyond it -- which is `Lab::Exits::Runner#ad_hoc_case`'s reading
    # and the same one here, so `no_new_ground` is judgeable on the promoted case
    # and a draw that opened nothing is flagged. On this subject that check is
    # nearly the point: an answer that opened nothing is an answer whose every
    # pick was discarded.
    lines << "  expects_new_ground: true"
    lines
  end

  # THE DANGER, IN THE ORDER IT IS TRUSTED: what he declared on the vantage, then
  # what every draw was actually born at when they agree, then nothing and a
  # note. Never a value nobody chose --
  # `Lab::Realization::Promotion#danger_line`'s rule, and the corpus validator is
  # what refuses the case until a person picks.
  def danger_line
    return "  danger: #{scalar(danger)}" if danger

    "  # danger: #{drawn_dangers.first || Location::SAFE}"
  end

  def danger
    return vantage.danger if vantage.danger.present?

    drawn_dangers.one? ? drawn_dangers.first : nil
  end

  def drawn_dangers
    @drawn_dangers ||= samples.reject(&:failed?).filter_map { |sample| sample.reading.facts["danger"] }
                              .compact_blank.uniq.sort
  end

  # THE PLACES OFF THE BOOKS, ONE PER LINE AND NEVER JOINED. A place name may
  # hold a comma -- the corpus already stages a world holding `Grenn's Boarding
  # House, Room 3` -- and `Lab::Exits::Vantage#absent_names` splits on newlines
  # for that reason, so a joined list here would split one place into two names
  # no world has and `Eval::Realization::Stage` would refuse the whole case.
  def absent_lines
    return [] if vantage.absent_names.empty?

    [ "  absent:", *vantage.absent_names.map { |name| "  - #{scalar(name)}" } ]
  end

  # THE QUANTIFIER, UNDER THE CORPUS'S OWN KEY. Left out when he declared none,
  # which the corpus reads as *don't care* -- and `#quantifier_note` says what
  # that costs, because a case with no label is out of both inside checks'
  # denominators and a promotion whose one durable claim is missing is a case
  # that measures nothing this lab was built for.
  #
  # AND THE POPULATION SET COMES TOO, under `expects_exit_population`, because it
  # is a vantage-wide subset of a closed list rather than anything keyed on a
  # name a model chose: the same shape `Lab::Realization::Promotion` emits from a
  # kind, and durable for the same reason.
  def expectation_lines
    lines = []
    lines << "  expects_inside: #{scalar(vantage.expects_inside_quantifier)}" if vantage.quantifier
    labels = vantage.expects_population_labels
    if labels
      key = Eval::Realization::Corpus.expectation_key(Lab::Exits.pick("population"))
      lines.concat([ "  #{key}:", *labels.map { |label| "  - #{scalar(label)}" } ])
    end
    lines
  end

  # THE PROVENANCE: when, how many draws, how many different answers they were,
  # what the rate was and what the counter-figure said. His own verdicts go in
  # beside it as the tallies they are and never folded into the rate --
  # `Lab::Exits::HitRate`'s rule, because one says whether the picks were what he
  # asked for and the others whether the answer was any good.
  #
  # AGENTS.md's rule is that a measured figure lives in a stored set or a test
  # and never in prose, and these are neither an assertion nor a thing anything
  # reads: they are the answer to *where did this case come from*, which is what
  # `why` is for. Nothing recomputes them and nothing compares against them.
  def why_lines
    sentences = [ "Typed in the exits lab as #{vantage.name.inspect} and scored there.",
                  "Drawn #{hit_rate.drawn} #{"time".pluralize(hit_rate.drawn)} up to #{@today.iso8601}, " \
                  "#{hit_rate.distinct_answers} of them different answers.",
                  quantifier_sentence, reach_sentence, verdict_sentence,
                  "The figures are the lab's provenance for this case and nothing reads them." ]
    folded("why", sentences.compact_blank.join(" "))
  end

  def quantifier_sentence
    figure = hit_rate.quantifier
    return "No quantifier was declared, so the vantage has no rate over its answers." if figure.nil?
    return "No draw answered the exits call, so the quantifier earned no denominator." unless figure.judgeable?

    "Its #{figure.allowed.inspect} quantifier held on #{figure.fraction} of the draws that answered" \
      "#{figure.established? ? "" : ", which is not established"}."
  end

  def reach_sentence
    reach = hit_rate.reach
    return nil unless reach.judgeable?

    "Over every draw: #{reach.named} places named, #{reach.given} given an inside, #{reach.reaching} of " \
      "those reaching the world."
  end

  def verdict_sentence
    tallies = [ tally("on the answers", hit_rate.verdicts), tally("on the places", hit_rate.place_verdicts) ]
    return nil if tallies.compact.empty?

    "His own verdicts #{tallies.compact.join("; ")}."
  end

  def tally(where, counted)
    return nil if counted.empty?

    "#{where}: #{counted.map { |word, count| "#{count} #{word}" }.join(", ")}"
  end

  def danger_note
    return nil if danger

    seen = drawn_dangers.presence&.join(", ") || "nothing drawn yet"
    "  # ^ CHOOSE A DANGER and uncomment the line. This vantage left it to the roll, so there is no " \
      "reproducible value to read off its draws (#{seen}). A promoted case must declare one, and the " \
      "corpus validator refuses it until it does."
  end

  # THE ONE NOTE THAT IS ABOUT THE PROMOTION ITSELF RATHER THAN ABOUT A KEY. A
  # vantage with no quantifier is worth drawing -- the judgements are the other
  # half and cost nothing -- but it is not worth promoting, because the case
  # would carry no claim either inside check could be judged on.
  def quantifier_note
    return nil if vantage.quantifier

    "  # `expects_inside` is left out: this vantage declared no quantifier, so the case carries no " \
      "claim about the inside pick and BOTH of the scorer's inside checks are out of its denominator. " \
      "Declare one at /lab/exits/vantages/#{vantage.id} -- it is free and retroactive -- and promote again."
  end

  def established_note
    figure = hit_rate.quantifier
    return nil if figure.nil? || figure.established?

    "  # NOT ESTABLISHED: the quantifier has #{figure.fraction} behind it and " \
      "Lab::Exits::MIN_DRAWS calls #{Lab::Exits::MIN_DRAWS} draws established. The case is still a " \
      "regression case for the claim; the claim is just less well evidenced than the file's others."
  end

  # AND THE MEASURED WARNING, because a vantage promoted with nothing off the
  # books re-runs the very draw the lab was built to stop him buying: four bought
  # draws of such a vantage opened zero new places and every `inside` pick was
  # thrown away (`data/ta-exits-lab-scout/report.md` section 2.2).
  def absent_note
    return nil if vantage.absent_names.any?

    "  # NOTHING IS OFF THE BOOKS on this vantage, so every pick about a place its world already holds " \
      "will be discarded by Location::Generator#connect_exit! and the ceiling half of the inside checks " \
      "may never see a building at all. Lab::Exits' header has the four bought draws that measured it."
  end

  def per_name_note
    typed = vantage.judgements.count(&:expectation?)
    judged = vantage.judgements.count(&:verdict?)
    return nil if typed.zero? && judged.zero?

    "  # #{typed} typed per-place expectation#{"s" unless typed == 1} and #{judged} " \
      "judgement#{"s" unless judged == 1} STAY IN THE LAB and are not in this case. A bench label keyed " \
      "on a name the model chose is a fact about what one model said one month, not about the world -- " \
      "Lab::Exits::Promotion's header carries the measurement. The quantifier is what they were used to " \
      "write."
  end

  def population_note
    return nil if vantage.expects_population_labels.nil?

    "  # `#{Eval::Realization::Corpus.expectation_key(Lab::Exits.pick("population"))}` is carried and " \
      "digested, and nothing scores it yet -- the figure over a case's `expects_*` block is the " \
      "agreement half of the plan and is filed apart (Eval::Realization::Corpus's header)."
  end
end
