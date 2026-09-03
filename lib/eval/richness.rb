# WHAT THE PROSE COMMITTED TO, counted, and printed beside the defect counts so
# a defect count that fell can be checked against what it cost.
#
# WHY THIS EXISTS AT ALL. Every check in `Story::Audit` asks whether the
# narration contradicted the records. There is a trivial way to never
# contradict them: say nothing. "The room is quiet. You wait." names no exit,
# handles no object, addresses nobody, and is unfalsifiable by construction. It
# would score a perfect board and destroy the game, and it is the FIRST thing
# anything optimising a contradiction rate will find. So the rate is never
# reported on its own.
#
# WHAT IS COUNTED, and why these four. A commitment is the prose naming
# something the RECORDS KNOW: the room the player is in, an exit out of it, a
# thing lying here or in their hands, a person in the room with them. Those are
# the four vocabularies the app can check the prose against, which makes them
# exactly the four a thinning narrator stops using. Counting them needs no
# model, no taste and no judgement -- it is set intersection against the same
# records `Story::Audit` reads.
#
# IT IS NOT A QUALITY SCORE AND MUST NOT BECOME ONE. Nothing here says the
# prose is good. A passage can name every exit in the room and still be bad
# writing, and this would score it highly. It answers one question -- did the
# narration engage with the world, or retreat from it -- and that question is
# the counterweight to the defect counts, not a second opinion about them.
#
# MEASURED, AND ONE OBVIOUS FIGURE MEASURED AND DISCARDED.
# `test/fixtures/files/whole_run_corpus.json` is the same eleven-command run
# played by four models, 132 real narrations, median lengths 423 to 720
# characters. Two things came out of pointing this at them, and the second one
# changed the design:
#
#   1. THINNING PROSE DROPS IT, which is the property the whole thing needs.
#      Cut every one of the 132 back to its first sentence -- what non-committal
#      prose actually looks like -- and mean commitments fall from 1.48 a turn
#      to 0.80, a 46% drop. `Eval::RichnessTest` is that experiment.
#
#   2. COMMITMENTS PER HUNDRED WORDS IS THE WRONG HEADLINE AND IS GONE. It was
#      the obvious normalisation and it is backwards: the two SHORTEST arms
#      score HIGHEST on it (mistral 2.86, gemini 2.38, against minimax 1.09 and
#      kimi 1.01), because dividing by length rewards terseness -- which is the
#      exact behaviour this metric exists to catch. Thinning the corpus RAISES
#      it, from 1.33 to 4.08. A counter-metric that goes up when the prose goes
#      thin is worse than none.
#
# So the headline is the MEAN COMMITMENTS PER TURN, with COVERAGE -- the share
# of what was available that the passage used -- beside it, because a world with
# six nameable things and a world with twenty are not comparable on a raw count.
#
# THE THIRD FINDING, reported because it contradicts the assumption the metric
# was commissioned under: LENGTH IS NOT A PROXY FOR COMMITMENT. The two long
# arms commit to LESS per turn than the two short ones (1.33 and 1.18 against
# 1.76 and 1.64). Long prose here is long in atmosphere, not in world-reference.
# That is a good property of the metric -- it is not a character counter -- and
# it means "the prose got longer" must never be read as "the prose committed to
# more".
#
# AND IT IS GAMEABLE IN THE OTHER DIRECTION, stated so nobody optimises it
# alone: "You are in Ward Office 12; the supply closet and the long hallway are
# here" scores three commitments and is not prose anybody wants. It is a
# counterweight to the defect counts and is never a target on its own.
module Eval::Richness
  extend self

  # THE RECORDS A PASSAGE IS READ AGAINST. Names only -- this holds no rows, so
  # the live database and a checked-in fixture reach the same code, which is the
  # rule `Story::Audit::Prose` already follows.
  Vocabulary = Data.define(:room, :exits, :items, :characters) do
    def self.empty = new(room: nil, exits: [], items: [], characters: [])

    # How many separate things this turn offered the prose to name.
    def size = (room.present? ? 1 : 0) + exits.size + items.size + characters.size
  end

  # ONE PASSAGE'S READING. Counts of DISTINCT things named, never of mentions:
  # a narration that says "the daybook" four times committed to one object.
  #
  # `available` is how many nameable things the records put within reach on this
  # turn, and it is carried so `coverage` can be worked out without the
  # vocabulary -- a scored run outlives the database it came from.
  Reading = Data.define(:chars, :words, :sentences, :room, :exits, :items, :characters, :available) do
    def commitments = room + exits + items + characters

    # THE SHARE OF WHAT WAS THERE. A room with two exits and one item offers
    # four things to commit to and a crossroads with six offers eight, so the
    # raw count is not comparable across worlds and this is.
    def coverage = available.zero? ? 0.0 : commitments.fdiv(available)

    def to_h = { chars:, words:, sentences:, room:, exits:, items:, characters:,
                 available:, commitments:, coverage: coverage.round(4) }
  end

  # Read `text` against a vocabulary of names. Every name is matched by the
  # aliases `Story::Audit::Prose` derives -- "Ward Office 12" is written as "the
  # office" and "Ward Office 12 daybook" as "the daybook", and a counter that
  # missed those would score a committed passage as an empty one.
  def read(text, vocabulary)
    body = text.to_s

    Reading.new(
      chars: body.length,
      words: body.split(/\s+/).count { |word| word.match?(/[[:alpha:]]/) },
      sentences: Story::Audit::Prose.sentences(body).count { |line| line.strip.present? },
      room: vocabulary.room.present? && named?(body, Story::Audit::Prose.place_names(vocabulary.room)) ? 1 : 0,
      exits: count_named(body, vocabulary.exits) { |name| Story::Audit::Prose.place_names(name) },
      items: count_named(body, vocabulary.items) { |name| Story::Audit::Prose.item_names(name) },
      characters: count_named(body, vocabulary.characters) { |name| Story::Audit::Prose.character_names(name) },
      available: vocabulary.size
    )
  end

  # THE RECORDS AROUND ONE STORED TURN, as the game had them when it was
  # narrated. The protagonist is left out of the cast on purpose: the player is
  # "you", and a narration that names them is `third_person_protagonist`, a
  # defect -- it must not also earn a point here.
  def vocabulary_for(scene)
    location = scene.location
    protagonist = scene.story&.protagonist

    Vocabulary.new(
      room: location&.name,
      exits: location ? location.exits.map(&:name) : [],
      items: items_around(scene).map(&:name),
      characters: (scene.characters.to_a - [ protagonist ].compact).map(&:fullname)
    )
  end

  def for_scene(scene) = read(scene.description, vocabulary_for(scene))

  # WHAT IS WITHIN REACH: the things lying in this room and the things in the
  # player's hands. An item in another room is not something this passage could
  # have committed to, and counting it would punish a narration for staying
  # where it is.
  def items_around(scene)
    protagonist = scene.story&.protagonist
    here = scene.location ? Item.lying_in(scene.location).to_a : []
    carried = protagonist ? Item.for_character(protagonist).to_a : []

    (here + carried).uniq { |item| item.name.to_s.downcase }
  end

  # A RUN, AS ONE ROW.
  #
  # Commitments and coverage are MEANS and length is a MEDIAN, and the mixture
  # is deliberate. Commitments per turn are small integers -- 0, 1, 2 -- so the
  # median is 1 for almost every run and cannot see a change; the mean can, and
  # it is the figure that fell 46% when the corpus was thinned. Length is the
  # opposite: an arrival narration is three times a talk turn, so its mean is
  # mostly a statement about how many arrivals the script had, and the median is
  # the honest middle.
  Summary = Data.define(:turns, :chars, :words, :commitments, :coverage,
                        :room, :exits, :items, :characters) do
    def to_h = { turns:, chars:, words:, commitments:, coverage:,
                 room:, exits:, items:, characters: }
  end

  EMPTY_SUMMARY = Summary.new(turns: 0, chars: 0, words: 0, commitments: 0.0, coverage: 0.0,
                              room: 0.0, exits: 0.0, items: 0.0, characters: 0.0)

  def summarize(readings)
    rows = Array(readings)
    return EMPTY_SUMMARY if rows.empty?

    Summary.new(
      turns: rows.size,
      chars: median(rows.map(&:chars)).round,
      words: median(rows.map(&:words)).round,
      commitments: mean(rows.map(&:commitments)).round(3),
      coverage: mean(rows.map(&:coverage)).round(4),
      room: mean(rows.map(&:room)).round(3),
      exits: mean(rows.map(&:exits)).round(3),
      items: mean(rows.map(&:items)).round(3),
      characters: mean(rows.map(&:characters)).round(3)
    )
  end

  def mean(values) = Eval.mean(values)

  def median(values) = Eval.median(values)

  private

  def count_named(body, names)
    Array(names).count { |name| named?(body, yield(name)) }
  end

  def named?(body, aliases)
    Array(aliases).any? { |name| name.present? && body.match?(/\b#{Regexp.escape(name)}\b/i) }
  end
end
