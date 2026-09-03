require "test_helper"

# `unrecorded_arrival`, MEASURED THE WAY EVERY OTHER CHECK HERE WAS.
#
# The rule this project works to (`Story::Audit`'s header, and PR 99, which
# killed five plausible candidates on measurement) is that a check ships with a
# false-positive rate measured on real prose and a positive case that actually
# fires. This is both, for the check `ta-eval-pipeline` added.
#
# THE FALSE-POSITIVE MEASUREMENT: 224 real passages, ZERO FLAGS.
#
#   92   `eval_corpus.json` -- every stored Scene description and Interaction
#        action from the two worlds the captain played, plus the 24 lab
#        narrations written against commands designed to break a world's laws
#   132  `whole_run_corpus.json` -- the whole-run narrations of the four-arm
#        sweep, twelve complete eleven-turn playthroughs
#
# Across those, the grammar DETECTS 7 arrival assertions and every one of the 7
# names the room the records had already moved the player into, so the check
# raises nothing. That is the number that matters and it is also the number that
# looks identical to a check that cannot fire -- so the detections are asserted
# separately from the flags, and the positive case below takes one of those real
# sentences and moves the record underneath it.
#
# AN EIGHTH REAL ARRIVAL IS GIVEN UP TO THE NEGATION GUARD, on purpose and on
# the same trade `Story::Audit#possession_claimed?` already takes:
#
#   "You step back into the office to find Vance still standing motionless at
#    their desk, pen hovering above an untouched page, as if the last two
#    minutes never passed."
#
# The "never" is about the two minutes and not about the walking, and no regex
# tells those apart. It is pinned in `SACRIFICED` below so that a future change
# which catches it gets noticed and re-judged rather than silently widening the
# rule. (That sentence is a `third_person_protagonist` violation too, and that
# check does catch it.)
class Story::Audit::ArrivalTest < ActiveSupport::TestCase
  EVAL_CORPUS = JSON.parse(Rails.root.join("test/fixtures/files/eval_corpus.json").read).freeze
  RUN_CORPUS = JSON.parse(Rails.root.join("test/fixtures/files/whole_run_corpus.json").read).freeze

  # The places each world has, read out of the seed files -- the same records
  # `Story::Audit` reads, without needing rows.
  WORLDS = Rails.root.glob("db/seeds/worlds/*.yml").to_h do |file|
    document = YAML.safe_load_file(file, permitted_classes: [ Date, Time ])
    [ document.dig("story", "title"), document.fetch("locations").map { |row| row.fetch("name") } ]
  end.freeze

  def names_for(world)
    rooms = WORLDS.fetch(world)
    claimed = Hash.new(0)
    rooms.each { |room| Story::Audit::Prose.place_names(room).each { |name| claimed[name.downcase] += 1 } }

    rooms.flat_map { |room| Story::Audit::Prose.place_names(room).map { |name| [ name, room ] } }
         .reject { |name, _| claimed[name.downcase] > 1 }
         .to_h
  end

  # Every arrival assertion in a corpus, with the room the records had.
  def detections
    rows = EVAL_CORPUS.map { |row| [ row["story"], row["room"], row["text"] ] } +
           RUN_CORPUS.map { |row| [ row["world"], row["room"], row["text"] ] }

    rows.flat_map do |world, room, text|
      next [] unless WORLDS.key?(world)

      names = names_for(world)
      Story::Audit::Prose.arrival_claims(text, names.keys).map do |arrival|
        { world:, room:, claimed: names.fetch(arrival.name), sentence: arrival.sentence }
      end
    end
  end

  test "the two corpora are the 224 real passages this was measured on" do
    assert_equal 92, EVAL_CORPUS.size
    assert_equal 132, RUN_CORPUS.size
  end

  # THE HEADLINE. Every arrival the grammar found was one the records agreed
  # with, so the check flags nothing on 224 real passages.
  test "on 224 real passages every arrival the grammar finds is one the records made" do
    wrong = detections.reject { |row| row[:claimed] == row[:room] }

    assert_empty wrong, wrong.map { |row| "#{row[:room]} -> #{row[:claimed]}: #{row[:sentence]}" }.join("\n")
  end

  # AND IT IS NOT A CHECK THAT CANNOT FIRE, which is the failure mode that looks
  # exactly like the result above. Eight real sentences match the grammar.
  test "the grammar really does find arrival assertions in real prose" do
    found = detections

    assert_equal 7, found.size, found.map { |row| row[:sentence] }.join("\n")
    assert(found.all? { |row| row[:sentence].match?(/\byou\b/i) })
  end

  SACRIFICED = "You step back into the office to find Vance still standing motionless".freeze

  test "the one real arrival the negation guard gives up is still given up" do
    passage = RUN_CORPUS.find { |row| row["text"].include?(SACRIFICED) }
    assert passage, "the corpus no longer holds the sentence this trade was measured on"

    claims = Story::Audit::Prose.arrival_claims(passage.fetch("text"), names_for(passage.fetch("world")).keys)

    assert_empty claims,
                 "this one is now caught -- read it, confirm the guard is still right, and move it into the count"
  end

  # THE POSITIVE CASE, on those same real sentences with the record moved: the
  # narration says the player walked into the office and the records have them
  # somewhere else. This is the captain's `ta-narrator-invents-exit` -- "the
  # narrator asserts state changes the game never records" -- caught from the
  # front, where `unrecorded_departure` catches it from behind.
  test "the same real sentences flag when the records put the player elsewhere" do
    story = seeded("The Unrecorded Hour")
    office = story.locations.find_by!(name: "Ward Office 12")
    closet = story.locations.find_by!(name: "The Supply Closet")

    sentence = "You step back into the office, and the mantle is still hissing over the two desks."
    scene = played(story, closet, sentence, after: story.opening_scene)

    flags = Story::Audit.new(story, scenes: story.scenes.where(id: scene.id)).flags

    assert_equal [ :unrecorded_arrival ], flags.map(&:code)
    assert_match(/Ward Office 12/, flags.first.headline)
    assert_match(/The Supply Closet/, flags.first.headline)
    assert_equal "in #{closet.name}", flags.first.evidence["records say"]
    assert_equal office.name, flags.first.headline[/into "([^"]+)"/, 1]
  end

  test "arriving where the records DID put the player is not flagged" do
    story = seeded("The Unrecorded Hour")
    office = story.locations.find_by!(name: "Ward Office 12")

    scene = played(story, office, "You step back into the office, and the mantle is still hissing.",
                   after: story.opening_scene)

    assert_empty Story::Audit.new(story, scenes: story.scenes.where(id: scene.id)).flags
  end

  # THE LINE THIS CHECK MUST NOT CROSS. `Story::Audit`'s first measured finding
  # is that a mention is not a claim -- prose refers to places through windows
  # and doorways all the time -- and the whole reason a preposition and a
  # movement verb are required is to stay on the right side of it.
  test "naming a place without walking into it is not an arrival" do
    story = seeded("The Unrecorded Hour")
    closet = story.locations.find_by!(name: "The Supply Closet")

    [
      "The door to the office stands open on the darkening corridor.",
      "Ward Office 12 is visible through the gap, the mantle still burning.",
      "You look out towards the office and see nothing move.",
      "You lean towards the office door without opening it.",
      "You do not step into the office; the shelves keep you where you are."
    ].each do |passage|
      scene = played(story, closet, passage, after: story.opening_scene)

      assert_empty Story::Audit.new(story, scenes: story.scenes.where(id: scene.id)).flags,
                   "flagged a mention rather than a claim: #{passage}"
    end
  end

  # A name two rooms answer to cannot say which room it meant, so it is dropped
  # rather than guessed at.
  test "an alias two rooms share is not used" do
    assert_equal %w[The\ Long\ Hallway Hallway], Story::Audit::Prose.place_names("The Long Hallway")

    story = seeded("The Unrecorded Hour")
    story.locations.create!(name: "The Service Hallway", detail_level: :stub, teaser: "Another one.")

    names = Story::Audit.new(story).send(:place_names)

    assert_not names.key?("Hallway"), "two rooms answer to it, so a flag could not say which"
    assert names.key?("The Long Hallway")
  end

  # A room whose last word is an ordinary English word for anywhere at all
  # contributes no alias, or "you step into the room" would be an arrival claim
  # about a specific location every time the prose used the word.
  test "a generic last word earns no alias" do
    assert_equal [ "The Waiting Room" ], Story::Audit::Prose.place_names("The Waiting Room")
    assert_equal [ "The Upper Floor" ], Story::Audit::Prose.place_names("The Upper Floor")
    assert_equal [ "Ward Office 12", "Office" ], Story::Audit::Prose.place_names("Ward Office 12")
  end

  private

  def seeded(title)
    @seeded ||= WorldSeed::Loader.load_all(io: nil).index_by(&:title)
    @seeded.fetch(title)
  end

  def played(story, room, description, after:)
    Scene.create!(story: story, location: room, previous_scene: after, description: description,
                  typed: "walk", summary: "a turn written by this test",
                  story_timestamp: (after&.story_timestamp || story.start_time) + 5.minutes)
  end
end
