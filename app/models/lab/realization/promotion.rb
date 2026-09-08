# A SCORED KIND, WRITTEN OUT AS A CORPUS CASE FOR A PERSON TO COMMIT.
#
# THE HALF OF THE CAPTAIN'S ASK THIS FILE IS, verbatim, 2026-09-07: *"I can run
# through a set of samples, score them and then we can use that to create
# alignment and then **maintain alignment in the future**."* The lab creates the
# alignment -- a kind, an expectation, a rate. Maintaining it means the same kind
# being re-run against a changed prompt, and only `Eval::Realization`'s corpus
# can do that. This is the one step between the two.
#
# IT EMITS TEXT AND WRITES NOTHING. `test/fixtures/files/realization_corpus.yml`
# is a checked-in measurement input: every case in it moves
# `Eval::Realization.digest`, and a moved digest invalidates the checked-in
# baseline and fails `Eval::Realization::KeptSetTest` until a new set is bought
# and pinned. That is a SPEND DECISION, so the last step has to be a person
# reading a diff and committing it -- a task that appended to the file itself
# could put the tree out of baseline as a side effect of somebody looking at a
# lab page. The rule is `Update::REGISTRY`'s in spirit: the automatic part stops
# where the money starts.
#
# WHAT IT CARRIES ACROSS, and the line is Call 4's: THE CASE CARRIES THE STUB.
# The room's own facts -- its name, its teaser, the `inside` band and the
# `population` word a real exits call would have supplied, and its danger -- plus
# the captain's `expects_*` block. Never a world fact: the universe, the preface,
# the places that already exist and the names already spoken for are all still
# read out of the records the world really holds when the case is staged
# (`Eval::Realization::Corpus`'s header draws that line and this obeys it).
#
# THE PROSE VERDICT IS NOT CARRIED, and that is Call 5 rather than an omission.
# `Eval::Realization::UNAVAILABLE_TO_A_REALIZATION` names *is the description any
# good* as a refusal: there is no deterministic reader of whether a paragraph is
# worth reading, a judge model would be a second model to keep honest, and the
# repo has the receipts -- two prose-reading checks died on the narration corpus
# and `door_the_records_do_not_hold` was retired after six grammars. So his
# verdict on the prose stays in the lab and in the report, and no check reads it.
#
# THE DANGER IS THE ONE FACT THIS FILE MAY HAVE TO ASK HIM FOR. A promoted case
# MUST declare one (`Eval::Realization::Corpus#stub_problems`): the roll a new
# room would get is keyed on the story's id, which a staged copy of a world is
# issued afresh on every load, so an undeclared danger would move the prompt
# digest between two runs of one tree. A kind that declared one hands it over; a
# kind that left it to the roll has its samples read instead, and if THOSE
# disagree the emitted case carries a commented line naming what was seen rather
# than a value nobody chose. The corpus validator then refuses the case until a
# person picks -- which is the right place for that to be noticed.
#
# AND THE `why` CARRIES THE PROVENANCE AND NOT A CLAIM. AGENTS.md's rule is that
# a measured figure lives in a stored set or a test and never in prose, and the
# date, the draw count and the hit rate written into a `why` are neither an
# assertion nor a thing anything reads: they are the answer to *where did this
# case come from*, which is exactly what `why` is for. Nothing recomputes them
# and nothing compares against them.
class Lab::Realization::Promotion
  # THE SHAPE A PROMOTED CASE IS GROUPED UNDER. `Lab::Realization::Runner::SHAPE`'s
  # reasoning, one step along: a lab draw is `lab`, so a case promoted out of the
  # lab says so too rather than masquerading as one of the corpus's own shapes --
  # every one of which is a claim about what the STAGING produces (a written
  # neighbour, a dead end, a room already partly connected) and none of which a
  # typed stub can make.
  #
  # IT IS A NEW SHAPE, WHICH MEANS A NEW DESIGNATED CASE.
  # `Eval::Realization::Version` digests the prompts of the lowest-id case of each
  # shape, so the first promoted case committed becomes one of them and the prompt
  # digest moves with it. That is correct -- a promoted case really does send a
  # prompt the corpus could not send before -- and it is said here because it is
  # the kind of movement a reader would otherwise credit to a prompt edit.
  SHAPE = "lab-promoted".freeze

  # THE ID PREFIX, so a case's origin is legible in a board's leftmost column
  # without anybody reading the `why`.
  ID_PREFIX = "lab".freeze

  attr_reader :kind, :samples

  def initialize(kind, today: Date.current)
    @kind = kind
    @samples = kind.samples.in_draw_order.to_a
    @today = today
  end

  def id = "#{ID_PREFIX}-#{kind.name.parameterize}"

  # THE CASE AS YAML, ready to paste under `cases:`. Built by hand rather than
  # through `YAML.dump` because the comments are half of what a person reads --
  # which key had to be chosen, which expectation could never be answered, and
  # what the figures behind the `why` were.
  def to_yaml
    lines = [ "# Promoted out of the realization lab on #{@today.iso8601}. Read it, then commit it.",
              "- id: #{id}" ]
    lines.concat(fact_lines)
    lines.concat(expectation_lines)
    lines << "  shape: #{SHAPE}"
    lines.concat(why_lines)
    lines.concat(notes)
    "#{lines.join("\n")}\n"
  end

  # WHAT A PERSON HAS TO SETTLE BEFORE THE CASE VALIDATES, as sentences. Empty
  # when the kind hands over everything a case needs.
  def notes
    found = []
    if danger.nil?
      seen = drawn_dangers.presence&.join(", ") || "nothing drawn yet"
      found << "  # ^ CHOOSE A DANGER and uncomment the line. This kind left it to the roll, so there " \
               "is no reproducible value to read off its samples (#{seen}). A promoted case must " \
               "declare one, and the corpus validator refuses it until it does."
    end
    kind.unanswerable.each do |pick|
      found << "  # `#{Eval::Realization::Corpus.expectation_key(pick)}` is left out: a " \
               "#{kind.place? ? "building" : "room"} is never asked this pick " \
               "(Lab::Realization::Kind#answerable?), so an expectation for it could never be earned."
    end
    if danger_floor_widens?
      found << "  # `#{Eval::Realization::Corpus::DANGER_FLOOR_KEY}` WIDENS this kind's expectation: " \
               "he allowed #{kind.expects("danger").join(", ")}, and a floor is every rung at or " \
               "above the quietest of them."
    end
    found
  end

  private

  def fact_lines
    lines = [ "  story: #{scalar(kind.world)}", "  room: #{scalar(kind.name)}" ]
    lines.concat(folded("teaser", kind.teaser))
    lines << "  reached_from: #{scalar(kind.reached_from)}" if kind.reached_from.present?
    lines << "  inside: #{scalar(kind.inside)}" if kind.inside.present?
    lines << "  population: #{scalar(kind.population)}" if kind.population.present?
    lines << danger_line
    # A KIND HE TYPED IS SOMEWHERE THE STORY POINTS INTO -- he typed it to see it
    # built -- which is `Lab::Realization::Runner#ad_hoc_case`'s reading and the
    # same one here, so `no_new_ground` is judgeable on the promoted case too.
    lines << "  expects_new_ground: true"
    lines
  end

  # THE DANGER, IN THE ORDER IT IS TRUSTED: what he declared on the kind, then
  # what every sample was actually drawn at when they agree, then nothing and a
  # note. Never a value nobody chose.
  def danger_line
    return "  danger: #{scalar(danger)}" if danger

    "  # danger: #{drawn_dangers.first || Location::SAFE}"
  end

  def danger
    return kind.danger if kind.danger.present?

    drawn_dangers.one? ? drawn_dangers.first : nil
  end

  def drawn_dangers
    @drawn_dangers ||= samples.reject(&:failed?).filter_map { |sample| sample.reading.facts["danger"] }
                              .compact_blank.uniq.sort
  end

  # HIS EXPECTATION, ONE KEY PER PICK HE DECLARED THAT THIS KIND CAN ACTUALLY BE
  # ASKED. A pick the call never offers is left out and named in `#notes`, on the
  # corpus's own rule for a key left out: *don't care* takes the case out of that
  # figure's numerator and its denominator both, and a rate a check did not earn
  # is worse than no rate.
  #
  # THE CORPUS'S OWN HAND LABEL `expects_inside` IS NEVER EMITTED FROM THE
  # `inside` PICK. They are different claims -- the label is about whether the
  # world AROUND this stub plainly holds a building, the pick is about the band
  # the model chose for each place it named as an exit -- and
  # `Lab::Realization::Pick`'s header says in so many words that the two must not
  # be confused in a promotion. Whoever commits the case may add the label by
  # hand where the answer is not a guess.
  def expectation_lines
    Eval::Realization::Corpus.picks.filter_map { |pick|
      next if !kind.answerable?(pick) || kind.expects(pick).nil?

      pick.name == "danger" ? danger_floor_line : list_lines(pick)
    }.flatten
  end

  def danger_floor_line
    "  #{Eval::Realization::Corpus::DANGER_FLOOR_KEY}: #{scalar(danger_floor)}"
  end

  # THE QUIETEST RUNG HE ALLOWED, which is what an ordinal floor means. A set
  # with a hole in it -- `safe` and `dangerous` but not `uneasy` -- cannot be
  # said as a floor at all, so the floor widens it and `#notes` says so rather
  # than the file quietly measuring something he did not ask for.
  def danger_floor
    allowed = kind.expects("danger") || []
    Location::Parameters::LADDER.find { |rung| allowed.include?(rung) }
  end

  def danger_floor_widens?
    allowed = kind.expects("danger")
    return false if allowed.nil? || !kind.answerable?(Eval::Realization::Corpus.danger_pick)

    Eval::Realization::Corpus.danger_at_least(danger_floor).sort != allowed.sort
  end

  def list_lines(pick)
    [ "  #{Eval::Realization::Corpus.expectation_key(pick)}:",
      *kind.expects(pick).map { |label| "  - #{scalar(label)}" } ]
  end

  # THE PROVENANCE: when, how many draws, and what the rate was. His own verdicts
  # go in beside it, as the tally they are and never folded into the rate --
  # `Lab::Realization::HitRate#verdicts`' rule, because one says whether the picks
  # were what he asked for and the other whether the room was any good.
  def why_lines
    rate = kind.hit_rate
    sentences = [ "Typed in the realization lab as #{kind.name.inspect} and scored there.",
                  "Drawn #{rate.drawn} #{"time".pluralize(rate.drawn)} up to #{@today.iso8601}.",
                  overall_sentence(rate), verdict_sentence(rate),
                  "The figures are the lab's provenance for this case and nothing reads them." ]
    folded("why", sentences.compact_blank.join(" "))
  end

  def overall_sentence(rate)
    overall = rate.overall
    return "No expectation was declared, so the kind has no hit rate." if overall.nil?
    return "Every declared pick was answered on no sample, so the kind has no overall rate." unless
      overall.judgeable?

    "Every declared pick came back the way he said it should on #{overall.fraction} of them" \
      "#{overall.established? ? "" : ", which is not established"}."
  end

  def verdict_sentence(rate)
    return nil if rate.judged.zero?

    "His own verdicts over the set: #{rate.verdicts.map { |word, count| "#{count} #{word}" }.join(", ")}."
  end

  # A BLOCK SCALAR FOR THE TWO LONG FIELDS, which is how every `why` in the
  # corpus is already written -- and `>-` rather than `|` because a teaser and a
  # `why` are prose and the line breaks are the file's, not the sentence's.
  def folded(key, text)
    return [] if text.blank?

    [ "  #{key}: >-", *text.to_s.squish.scan(/.{1,88}(?:\s|$)/).map { |chunk| "    #{chunk.strip}" } ]
  end

  # QUOTED WHENEVER YAML WOULD READ IT AS ANYTHING BUT A STRING, which for a room
  # somebody typed is more often than a reader expects: a name beginning with a
  # `#`, holding a `:` or spelled `no` is a comment, a mapping and a boolean.
  def scalar(value) = value.to_s.match?(/\A[A-Za-z][^:#]*\z/) ? value.to_s : value.to_s.inspect
end
