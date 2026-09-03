require "test_helper"

# THE COUNTER-METRIC, MEASURED AGAINST PROSE KNOWN TO BE THINNER.
#
# `Eval::Richness` exists to catch one specific way of gaming the defect counts:
# prose that says less contradicts less. That claim is only worth anything if
# the metric actually moves when prose thins, so this test is the demonstration
# rather than an assertion that the arithmetic works.
#
# THE CORPUS IS REAL AND WAS NOT WRITTEN FOR THIS.
# `test/fixtures/files/whole_run_corpus.json` is 132 narrations from the four-arm
# whole-run sweep of 2026-09-02: the same eleven-command script, against the same
# seeded world, played three times by each of four models. Their median lengths
# span 374 to 823 characters, which makes them a ready-made high/low pair with
# every other variable held.
#
# WHAT IS ASSERTED, and the middle one is the one that matters:
#
#   1. LENGTH IS NOT COMMITMENT, and the fixture proves it the wrong way round:
#      the two LONG arms commit to LESS per turn than the two short ones. Pinned
#      here because the metric was commissioned on the assumption that the
#      485-to-720-character span was a rich/thin pair, and it is not -- long
#      prose here is long in atmosphere.
#   2. THINNING REAL PROSE DROPS IT. Cut all 132 back to their first sentence --
#      what non-committal prose looks like -- and the mean falls by about half.
#      This is the hazard itself, tested on prose the models really wrote.
#   3. COMMITMENTS PER HUNDRED WORDS GOES THE WRONG WAY and is not the headline.
#      Pinned so nobody reintroduces it: thinning the corpus RAISES it.
class Eval::RichnessTest < ActiveSupport::TestCase
  CORPUS = JSON.parse(Rails.root.join("test/fixtures/files/whole_run_corpus.json").read).freeze

  # The records the corpus passages were written against, read out of the seed
  # file rather than the database: the fixture has to be scoreable with no rows
  # at all, which is the same rule `Story::Scoreboard::Corpus` follows.
  SEED = YAML.safe_load_file(Rails.root.join("db/seeds/worlds/the-unrecorded-hour.yml"), permitted_classes: [ Date, Time ]).freeze

  def vocabulary_for(room)
    exits = SEED.fetch("connections").filter_map do |edge|
      pair = edge.fetch("between")
      pair.first == room ? pair.last : (pair.last == room ? pair.first : nil)
    end
    protagonist = SEED.fetch("characters").find { |character| character["is_protagonist"] }

    Eval::Richness::Vocabulary.new(
      room: room,
      exits: exits,
      items: SEED.fetch("characters").flat_map { |character| Array(character["items"]).map { |item| item.fetch("name") } },
      characters: SEED.fetch("characters").reject { |character| character == protagonist }.map { |c| c.fetch("fullname") }
    )
  end

  def readings_of(&block)
    CORPUS.map { |row| Eval::Richness.read(block.call(row), vocabulary_for(row["room"])) }
  end

  def readings_by_arm
    CORPUS.group_by { |row| row["arm"] }.transform_values do |rows|
      rows.map { |row| Eval::Richness.read(row.fetch("text"), vocabulary_for(row["room"])) }
    end
  end

  test "the corpus is what it claims to be" do
    assert_equal 132, CORPUS.size
    assert_equal %w[gemini kimi minimax mistral], CORPUS.map { |row| row["arm"] }.uniq.sort
    assert_equal [ "The Unrecorded Hour" ], CORPUS.map { |row| row["world"] }.uniq
    assert(CORPUS.all? { |row| row["text"].present? && row["room"].present? })
  end

  # 1. LENGTH IS NOT COMMITMENT. The long arms are long in atmosphere: they
  # write half again as many words and name FEWER of the things the records
  # hold. Pinned because "the prose got longer" is exactly what somebody will
  # want to read as "the prose committed to more", and on this corpus it is the
  # opposite.
  test "the two arms that wrote most committed to least, so this is not a length counter" do
    summaries = readings_by_arm.transform_values { |readings| Eval::Richness.summarize(readings) }
    long = %w[kimi minimax]
    short = %w[gemini mistral]

    assert_operator short.map { |arm| summaries.fetch(arm).chars }.max, :<,
                    long.map { |arm| summaries.fetch(arm).chars }.min,
                    "the fixture is supposed to be a long/short pair on length"
    assert_operator long.map { |arm| summaries.fetch(arm).commitments }.max, :<,
                    short.map { |arm| summaries.fetch(arm).commitments }.min,
                    "commitments a turn: #{summaries.transform_values(&:commitments).inspect}"
  end

  # 2. THE HAZARD ITSELF, on all 132 real passages. Cutting a narration back to
  # its opening sentence is what an optimiser would discover: it keeps the
  # passage grammatical and drops everything it could be wrong about.
  test "thinning every real passage to its first sentence drops the metric by about half" do
    whole = Eval::Richness.summarize(readings_of { |row| row.fetch("text") })
    thinned = Eval::Richness.summarize(readings_of { |row| Story::Audit::Prose.sentences(row.fetch("text")).first.to_s })

    assert_operator thinned.commitments, :<, whole.commitments * 0.7,
                    "whole #{whole.commitments} a turn, thinned #{thinned.commitments}"
    assert_operator thinned.coverage, :<, whole.coverage
  end

  # 3. THE NORMALISATION THAT WAS MEASURED AND THROWN OUT, pinned so it cannot
  # come back by accident: dividing by length rewards exactly the prose this is
  # supposed to catch.
  test "commitments per hundred words rises when the prose thins, which is why it is not the headline" do
    density = lambda do |&block|
      rows = CORPUS.map { |row| Eval::Richness.read(block.call(row), vocabulary_for(row["room"])) }
      Eval::Richness.median(rows.map { |row| row.words.zero? ? 0.0 : row.commitments * 100.0 / row.words })
    end

    whole = density.call { |row| row.fetch("text") }
    thinned = density.call { |row| Story::Audit::Prose.sentences(row.fetch("text")).first.to_s }

    assert_operator thinned, :>, whole,
                    "thinning the corpus must raise the density -- that is the argument against using it"
    assert_not Eval::Richness::Summary.members.include?(:per_100_words),
               "the density is a diagnostic, not a reported figure"
  end

  test "a passage that names nothing the records know commits to nothing" do
    reading = Eval::Richness.read("It is quiet. You wait, and nothing happens.", vocabulary_for("Ward Office 12"))

    assert_equal 0, reading.commitments
    assert_equal 0.0, reading.coverage
  end

  test "coverage is the share of what the records actually offered" do
    vocabulary = vocabulary_for("Ward Office 12")
    reading = Eval::Richness.read("You are back in the office with your daybook.", vocabulary)

    assert_equal vocabulary.size, reading.available
    assert_in_delta 2.0 / vocabulary.size, reading.coverage, 0.0001
  end

  test "a name is counted once however often the prose says it" do
    once = Eval::Richness.read("The daybook lies open.", vocabulary_for("Ward Office 12"))
    thrice = Eval::Richness.read("The daybook lies open. The daybook is yours. You read the daybook.",
                                 vocabulary_for("Ward Office 12"))

    assert_equal 1, once.items
    assert_equal 1, thrice.items
  end

  # The aliases are what make this work at all: the records call it "Ward Office
  # 12 daybook" and no narration in 132 ever did.
  test "the aliases the records imply are what the prose is actually matched on" do
    vocabulary = vocabulary_for("Ward Office 12")

    assert_includes vocabulary.items, "Ward Office 12 daybook"
    assert_equal 1, Eval::Richness.read("Your daybook lies open under your hand.", vocabulary).items
    assert_equal 1, Eval::Richness.read("You are back in the office.", vocabulary).room
  end

  test "the protagonist is not a person the prose can be credited for naming" do
    story = FactoryBot.create(:story)
    protagonist = FactoryBot.create(:character, story: story, is_protagonist: true, fullname: "Odile Vance")
    other = FactoryBot.create(:character, story: story, is_protagonist: false, fullname: "Halkett Rowe")
    location = FactoryBot.create(:location, story: story)
    scene = FactoryBot.create(:scene, story: story, location: location, characters: [ protagonist, other ])

    vocabulary = Eval::Richness.vocabulary_for(scene)

    assert_equal [ "Halkett Rowe" ], vocabulary.characters
  end

  test "the summary is the median of the turns, not their mean" do
    readings = [ 10, 10, 10, 1000 ].map { |length| Eval::Richness.read("x" * length, Eval::Richness::Vocabulary.empty) }

    assert_equal 10, Eval::Richness.summarize(readings).chars
  end
end
