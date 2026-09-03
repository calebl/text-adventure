require "test_helper"

# THE PIPELINE, END TO END, WITH NO GENERATION AND NO DATABASE OF RUNS.
#
# Everything here is the offline half: a scored set round-trips through JSON, a
# board prints from it, and a comparison turns two of them into verdicts.
# GENERATION IS NOT EXERCISED AND MUST NOT BE -- it costs money and needs an
# API key, and the last test in this file is the guard that says so.
class Eval::PipelineTest < ActiveSupport::TestCase
  # ------------------------------------------------------------- the scripts
  test "every world the sweep plays has a script, and it is that world's" do
    Eval::STORIES.each do |title|
      script = Eval::Script.for(title)

      assert_equal title, script.story
      assert_operator script.size, :>=, 10, "#{title} is too short a run to measure anything on"
      assert(script.turns.all? { |turn| turn.command.present? && turn.id.present? })
      assert_equal script.turns.map(&:id).uniq.size, script.size, "#{title} has duplicate turn ids"
    end
  end

  # THE SCRIPTS ARE WHAT MAKE THE DORMANT CHECKS LIVE. A run that never moves
  # cannot exercise `unreachable_transition`; one that never carries anything
  # cannot exercise `item_not_held`; one that never reaches for something absent
  # cannot exercise `reached_for_nothing`. Asserted per world so a future edit
  # cannot quietly turn a script into eleven turns of looking at furniture.
  test "every script moves, talks, and reaches for something" do
    Eval::Script.all.each do |script|
      expectations = script.turns.map(&:expect).tally

      assert_operator expectations["move"].to_i, :>=, 3, "#{script.story} does not move enough to check transitions"
      assert_operator expectations["talk"].to_i, :>=, 3, "#{script.story} does not talk"
      assert_operator expectations["narrate"].to_i, :>=, 2, "#{script.story} never asks for the impossible"
    end
  end

  test "the two worlds with items put one down and pick it up again" do
    stories = WorldSeed::Loader.load_all(io: nil).index_by(&:title)

    Eval::STORIES.each do |title|
      next if Item.where(character: stories.fetch(title).characters).none?

      expectations = Eval::Script.for(title).turns.map(&:expect)

      assert_includes expectations, "drop", "#{title} has an item and never puts it down"
      assert_includes expectations, "take", "#{title} has an item and never picks one up"
    end
  end

  # THE COMMANDS NAME THE ITEM THE WAY THE RECORDS DO, which is not pedantry:
  # `Playthrough::IntentSchema` builds a closed enum out of the recorded names,
  # and a command that says "the daybook" resolves to nothing and costs the run
  # the branch it exists to exercise. See the note in the script files.
  test "a take or drop turn names the item as the records hold it" do
    stories = WorldSeed::Loader.load_all(io: nil).index_by(&:title)

    Eval::Script.all.each do |script|
      names = Item.where(character: stories.fetch(script.story).characters).pluck(:name)
      next if names.empty?

      script.turns.select { |turn| %w[take drop].include?(turn.expect) }.each do |turn|
        assert(names.any? { |name| turn.command.include?(name) },
               "#{script.story} #{turn.id} says #{turn.command.inspect} but the records call it #{names.inspect}")
      end
    end
  end

  test "the held-out world is one of the three and is not a tuning world" do
    assert_includes Eval::STORIES, Eval::HELD_OUT
    assert_not_includes Eval::TUNING, Eval::HELD_OUT
    assert_equal 3, Eval::STORIES.size
    assert Eval.held_out?(Eval::HELD_OUT)
    assert_not Eval.held_out?(Eval::TUNING.first)
  end

  test "every world the sweep plays is a world db/seeds/worlds actually ships" do
    seeded = WorldSeed.files.map { |file| YAML.safe_load_file(file, permitted_classes: [ Date, Time ]).dig("story", "title") }

    assert_empty Eval::STORIES - seeded
  end

  # --------------------------------------------------------- scores and board
  def reading(code, flagged, judgeable = 11, available: true)
    Eval::RunScore::Reading.new(code:, flagged:, judgeable:, unjudged: 0, available:)
  end

  def run_score(story:, rep:, flagged: 0, commitments: 1.5)
    Eval::RunScore.new(
      story: story, held_out: Eval.held_out?(story), rep: rep, turns: 11, scenes: 11,
      readings: Story::Scoreboard::CHECKS.keys.map do |code|
        code == :third_person_protagonist ? reading(code, flagged) : reading(code, 0)
      end,
      findings: Array.new(flagged) do |index|
        Eval::RunScore::Finding.new(code: :third_person_protagonist, story: story, turn: "t0#{index + 1}",
                                    typed: "look", headline: "the narration wrote the player as somebody else",
                                    claim: "Isbet Marrow does not wave back.", where: "a room",
                                    evidence: { "records say" => "the player is Isbet Marrow" })
      end,
      richness: Eval::Richness::Summary.new(turns: 11, chars: 500, words: 90, commitments: commitments,
                                            coverage: 0.3, room: 0.3, exits: 0.5, items: 0.2, characters: 0.4),
      usage: [ { model: "mistralai/mistral-medium-3.1", calls: 27, input_tokens: 19_000, output_tokens: 2_200 } ]
    )
  end

  def set_of(name, flags_per_run, commitments: 1.5)
    runs = flags_per_run.each_with_index.flat_map do |flagged, index|
      Eval::STORIES.map { |story| run_score(story: story, rep: index + 1, flagged: flagged, commitments: commitments) }
    end

    Eval::RunSet.new(name: name, runs: runs)
  end

  test "a scored run survives the trip through JSON, because a set outlives its databases" do
    original = run_score(story: Eval::HELD_OUT, rep: 2, flagged: 3)
    restored = Eval::RunScore.from_h(JSON.parse(JSON.generate(original.to_h)))

    assert_equal original.to_h, restored.to_h
    assert_equal 3, restored.flagged(:third_person_protagonist)
    assert restored.held_out?
    assert_in_delta 3 / 11.0, restored.rate(:third_person_protagonist), 0.0001
  end

  test "the board prints the noise floor, the rates, richness and the flagged turns" do
    output = StringIO.new
    Eval::Board.new(set_of("demo", [ 1, 2, 3, 4 ]), io: output).print(sample: 2)
    board = output.string

    assert_match(/THE NOISE FLOOR/, board)
    assert_match(/THE RATES, by corpus/, board)
    assert_match(/RICHNESS/, board)
    assert_match(/FLAGGED TURNS -- 30 in all, showing 2/, board)
    assert_match(/held out \(#{Regexp.escape(Eval::HELD_OUT)}\)/, board)
    assert_match(/\[HELD OUT\]/, board)
  end

  test "the board never pools the held-out world with the tuning worlds" do
    output = StringIO.new
    Eval::Board.new(set_of("demo", [ 1, 2 ]), io: output).print
    tuning, held = output.string.split("held out (#{Eval::HELD_OUT})", 2)

    assert tuning.include?("tuning (")
    assert held.present?
  end

  test "a board with nothing flagged says so in a way that reads as a warning" do
    output = StringIO.new
    Eval::Board.new(set_of("clean", [ 0, 0 ]), io: output).print

    assert_match(/NOTHING FLAGGED/, output.string)
    assert_match(/a claim about the\n  checks, not about the game/, output.string)
  end

  # ------------------------------------------------------------- comparisons
  test "a real improvement is called real and a repeat of the same runs is not" do
    before = set_of("before", [ 5, 6, 5, 6, 5 ])
    after = set_of("after", [ 1, 0, 1, 0, 1 ])

    verdict = Eval::Comparison.new(before, after).verdicts(stories: Eval::TUNING)
                              .find { |row| row.code == :third_person_protagonist }

    assert verdict.real?, verdict.headline
    assert verdict.improved?

    null = Eval::Comparison.new(before, set_of("again", [ 5, 6, 5, 6, 5 ]))
                           .verdicts(stories: Eval::TUNING).find { |row| row.code == :third_person_protagonist }

    assert null.noise?, null.headline
  end

  # THE CASE THE COUNTER-METRIC EXISTS FOR: fewer contradictions, bought with
  # prose that commits to measurably less. The report has to say so on the same
  # screen or the trade gets banked without being decided.
  test "an improvement paid for in blander prose is called out, not banked" do
    before = set_of("before", [ 5, 6, 5, 6, 5 ], commitments: 2.0)
    after = set_of("after", [ 1, 0, 1, 0, 1 ], commitments: 0.4)

    output = StringIO.new
    Eval::Comparison.new(before, after, io: output).print

    assert_match(/WARNING: third_person_protagonist improved AND the prose committed to measurably less/, output.string)
  end

  test "too few runs a side gets no verdict at all" do
    verdict = Eval::Comparison.new(set_of("before", [ 5, 6, 5 ]), set_of("after", [ 0, 0, 0 ]))
                              .verdicts(stories: [ Eval::HELD_OUT ]).find { |row| row.code == :third_person_protagonist }

    assert verdict.inconclusive?
    assert_match(/INCONCLUSIVE/, verdict.headline)
  end

  # ---------------------------------------------------------- what a script is
  #
  # THE CHECK THAT WOULD HAVE SAVED A PAID SWEEP. The first draft of the 20-turn
  # scripts talked to a character from the wrong room and reached for an item two
  # rooms away, because it was written as a list of good ideas rather than a
  # sequence of states. This asserts the sequence: every turn is reachable from
  # where the turn before it leaves the player.
  test "every script is a walkable sequence of rooms, not a list of good ideas" do
    stories = WorldSeed::Loader.load_all(io: nil).index_by(&:title)

    Eval::Script.all.each do |script|
      story = stories.fetch(script.story)
      here = story.opening_scene.location

      script.turns.each do |turn|
        next unless turn.expect == "move"

        named = story.locations.reject { |place| place == here }.find { |place| names_room?(turn.command, place) }

        assert named, "#{script.story} #{turn.id} is a move but names no room the story has: #{turn.command.inspect}"
        assert_not_equal here, named,
                         "#{script.story} #{turn.id} moves into #{named.name.inspect}, which is where the script already is"
        here = named
      end
    end
  end

  # AND THE ITEM TURNS FOLLOW THE ITEM. A `take` has to be in the room the last
  # `drop` left the thing in, which is the other half of the same mistake.
  test "every take is in the room the last drop left the item in" do
    stories = WorldSeed::Loader.load_all(io: nil).index_by(&:title)

    Eval::Script.all.each do |script|
      story = stories.fetch(script.story)
      next if Item.where(character: story.characters).none?

      here = story.opening_scene.location
      dropped_in = nil

      script.turns.each do |turn|
        if turn.expect == "move"
          here = story.locations.reject { |place| place == here }.find { |place| names_room?(turn.command, place) } || here
        elsif turn.expect == "drop"
          dropped_in = here
        elsif turn.expect == "take" && dropped_in
          assert_equal dropped_in, here,
                       "#{script.story} #{turn.id} takes the item in #{here.name.inspect}, " \
                       "but the script left it in #{dropped_in.name.inspect}"
        end
      end
    end
  end

  # THE CHECK THE CAPTAIN STRUCK, and why it is unavailable rather than zero:
  # *"if someone reaches for an item that is not there and the classifier
  # catches and the narrator says no, then everything is working correctly and
  # that should NOT be getting flagged as an issue."*
  # Same structural argument as the drift check: a script types a fixed line, so
  # whether it named two things is a fact about the yml file. A clean reading
  # would be the worse outcome -- 0 flagged out of every typed turn is a rate
  # the check never earned.
  test "named_more_than_one is unavailable on a scripted run, with the reason" do
    assert Eval.unavailable_to_a_script?(:named_more_than_one)
    assert_match(/measures the script's phrasing/, Eval::UNAVAILABLE_TO_A_SCRIPT[:named_more_than_one])
    assert_includes Story::Scoreboard::CHECKS.keys, :named_more_than_one,
                    "a check excluded from a sweep still has to be a check the board knows"
  end

  test "reached_for_nothing is unavailable on a scripted run, with the reason" do
    assert Eval.unavailable_to_a_script?(:reached_for_nothing)
    assert_match(/cannot be misled by prose/, Eval::UNAVAILABLE_TO_A_SCRIPT[:reached_for_nothing])
    assert_not Eval.unavailable_to_a_script?(:item_not_held), "the state checks still answer here"
  end

  test "no script reaches for something the world has not got" do
    stories = WorldSeed::Loader.load_all(io: nil).index_by(&:title)

    Eval::Script.all.each do |script|
      names = Item.where(character: stories.fetch(script.story).characters).pluck(:name)

      script.turns.select { |turn| %w[take drop].include?(turn.expect) }.each do |turn|
        assert(names.any? { |name| turn.command.include?(name) },
               "#{script.story} #{turn.id} reaches for something the records have not got, " \
               "which measures the script rather than the game")
      end
    end
  end

  # DOES THIS COMMAND NAME THIS ROOM -- a wider rule than
  # `Story::Audit::Prose.place_names`, on purpose. That one is deliberately
  # conservative because a false alias becomes a false FLAG; this one only has
  # to trace a script, and it has to cope with "Grenn's Boarding House, Room 3",
  # whose audit aliases are the full name alone (the last word is a digit and
  # the one before it is on the generic stop list).
  def names_room?(command, place)
    parts = Story::Audit::Prose.place_names(place.name) +
            place.name.split(",").map(&:strip).select { |part| part.length >= 4 }

    parts.uniq.any? { |name| command.match?(/#{Regexp.escape(name)}/i) }
  end

  # ------------------------------------------------------------- transcripts
  #
  # THE ANSWER TO "the clean board is confusing, how can I read it to verify?"
  # -- so what is asserted is that a clean turn is printed at all, which is the
  # one thing the board deliberately does not do.
  test "a transcript prints every turn, marks the flagged ones and keeps the clean ones" do
    turns = [
      Eval::Transcript::Turn.new(index: "t01", typed: "look at the slate", room: "The Causeway Court",
                                 prose: "You press your thumb to the chalked figure.", codes: [], branch: "narrate"),
      Eval::Transcript::Turn.new(index: "t02", typed: "walk out to the post", room: "The Tide Post",
                                 prose: "Coraith Vell stands at the post, her oilskin dark with spray.",
                                 codes: [ :third_person_protagonist ], branch: "move")
    ]
    output = StringIO.new
    Eval::Transcript.new(set: "main", story: Eval::HELD_OUT, rep: 1, turns: turns, io: output).print
    printed = output.string

    assert_match(/2 turns, 1 of them flagged/, printed)
    assert_match(/t01.*clean/, printed)
    assert_match(/t02.*FLAGGED third_person_protagonist/, printed)
    assert_match(/You press your thumb/, printed, "a clean turn's passage has to be printed -- that is the point")
    assert_match(/> look at the slate/, printed)
  end

  test "a transcript wraps the passages, because one is a single long line in the database" do
    turn = Eval::Transcript::Turn.new(index: "t01", typed: "look", room: "a room", codes: [], branch: "narrate",
                                      prose: (%w[word] * 200).join(" "))
    output = StringIO.new
    Eval::Transcript.new(set: "s", story: Eval::HELD_OUT, rep: 1, turns: [ turn ], io: output).print

    assert(output.string.lines.all? { |line| line.length <= 92 }, "a line came out too long to read")
  end

  # ------------------------------------------------------------------ money
  test "the estimate is priced from the registry rather than from a number in a comment" do
    Model.find_or_create_by!(model_id: "mistralai/mistral-medium-3.1", provider: "openrouter") do |model|
      model.name = "Mistral Medium 3.1"
    end.update!(pricing: { "text_tokens" => { "standard" => { "input_per_million" => 0.4, "output_per_million" => 2.0 } } })

    estimate = Eval::Cost.estimate(runs: 10, turns: 10, model: "mistralai/mistral-medium-3.1")

    assert_in_delta (100 * 1_800 * 0.4 + 100 * 300 * 2.0) / 1_000_000.0, estimate.dollars, 0.0001
    assert_equal 100 * Eval::Cost::PER_TURN[:input], estimate.input_tokens
  end

  test "a model the registry has never heard of is reported as unpriced rather than as free" do
    actual = Eval::Cost.actual([ { model: "somebody/else", calls: 1, input_tokens: 1000, output_tokens: 100 } ])

    assert_equal 0.0, actual.dollars
    assert_equal [ "somebody/else" ], actual.unpriced
  end

  # ------------------------------------------------------------------- CI
  #
  # GENERATION MUST NEVER RUN IN CI, and this is the guard rather than a note in
  # a README. Scoring is offline and free and runs everywhere; generating costs
  # real money and needs a key, and a suite that could spend it is a suite
  # nobody can run on a fork.
  test "the generation script is never loaded by the suite" do
    assert_not $LOADED_FEATURES.any? { |file| file.end_with?("script/eval_run.rb") }
    assert_not $LOADED_FEATURES.any? { |file| file.end_with?("script/eval_base.rb") }
  end

  test "the test environment has no API key, so a generation path would fail loudly rather than spend" do
    assert ENV["OPENROUTER_API_KEY"].blank?, "test_helper clears this; generation refuses to start without it"
    assert Rails.env.test?
  end

  test "the measurement manifest names files that exist" do
    missing = Eval::MEASUREMENT_FILES.reject { |relative| Rails.root.join(relative).exist? }

    assert_empty missing, "the manifest a future agent is told not to touch names files that are not there"
  end
end
