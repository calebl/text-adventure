require "test_helper"

# WHY THERE IS NO `character_not_present` CHECK, pinned rather than asserted in
# a commit message.
#
# `ta-character-whereabouts` landed the record that was supposed to make the
# check possible: `characters.location_id`, so "where is Ammon Brace" has an
# answer and the objection in `Story::Audit`'s finding 2a -- that a narrated
# turn records no cast, so every character reads as absent on it -- is gone.
# The check was then measured against EVALUATION.md's bar and it does not clear
# it. `Story::Audit`'s header, finding 5, has the argument; this file is the
# measurement, so that a later change to the corpora or to where the world
# files put people fails here and gets the decision re-read rather than
# inherited.
#
# NOTHING HERE TESTS `Story::Audit`, because there is nothing to test: no such
# check exists. Every assertion is about the DATA -- the frozen corpora and the
# checked-in world files -- which is what the decision actually rests on.
class Story::AuditPresenceTest < ActiveSupport::TestCase
  CORPORA = {
    "eval_corpus" => { path: "test/fixtures/files/eval_corpus.json", world: "story", room: "room", text: "text" },
    "narration_corpus" => { path: "test/fixtures/files/narration_corpus.json", world: "world", room: "room", text: "narration" },
    "whole_run_corpus" => { path: "test/fixtures/files/whole_run_corpus.json", world: "world", room: "room", text: "text" }
  }.freeze

  Passage = Data.define(:source, :world, :room, :text)

  # The one sentence in 248 passages that names somebody the checked-in world
  # files place in another room. It is a real defect and it is the check's
  # demonstrated positive case (EVALUATION.md, *Adding a check*, point 3): a
  # `move` turn into The Long Hallway whose prose is the previous turn's office
  # narration, with Halkett Rowe -- recorded in Ward Office 12 -- acting in it.
  DEMONSTRATED_POSITIVE = "Halkett's gaze moves to the book and then away".freeze

  # THE THREE SHAPES THAT KILL IT, all real prose from the frozen corpora, all
  # about a person who is in another room, and all correct. No grammar over a
  # name separates these from the sentence above, which is finding 2's result
  # and is not changed by the records becoming authoritative -- these are facts
  # about how prose refers to people, not about what the database knows.
  CORRECT_PROSE_ABOUT_SOMEBODY_ELSEWHERE = [
    # Audible from another room, and the narration says so itself.
    "From somewhere below, Grenn's voice rises in a muffled, irritated shout",
    # Habitual: a thing he does, not a thing he is doing here.
    "Grenn keeps the front door bolted after the tenth bell",
    # A PLACE whose name contains a person's name.
    "on the third floor of Grenn's boarding house"
  ].freeze

  def passages
    @passages ||= CORPORA.flat_map do |source, keys|
      JSON.parse(File.read(Rails.root.join(keys[:path]))).map do |row|
        Passage.new(source: source, world: row[keys[:world]], room: row[keys[:room]], text: row[keys[:text]].to_s)
      end
    end
  end

  # `{ world title => { fullname => room or nil } }`, straight off the files the
  # loader reads. The protagonist is excluded because they carry no whereabouts
  # at all -- the party is wherever the playthrough is; see `Character`.
  def seeded_whereabouts
    @seeded_whereabouts ||= WorldSeed.files.to_h do |path|
      document = WorldSeed.parse(File.read(path))
      cast = Array(document["characters"]).reject { |row| row["is_protagonist"] }

      [ document.dig("story", "title"), cast.to_h { |row| [ row["fullname"], row["location"] ] } ]
    end
  end

  # Who the records place somewhere OTHER than the room this passage happens
  # in. The candidate set, and the strongest one available: somebody nowhere is
  # unjudgeable and never a candidate.
  def elsewhere_in(passage)
    (seeded_whereabouts[passage.world] || {}).filter_map do |fullname, room|
      fullname if room.present? && room != passage.room
    end
  end

  def names?(text, fullname)
    Story::Audit::Prose.character_names(fullname).any? { |name| text.match?(/\b#{Regexp.escape(name)}\b/i) }
  end

  test "the corpora are the three EVALUATION.md names, at the sizes it states" do
    assert_equal({ "eval_corpus" => 92, "narration_corpus" => 24, "whole_run_corpus" => 132 },
                 passages.group_by(&:source).transform_values(&:size))
  end

  # THE DENOMINATOR, and it is the first half of why the check cannot ship: a
  # check can only be judged on a passage where somebody is demonstrably
  # elsewhere, and that is 36 of 248.
  test "only 36 of the 248 frozen passages can judge a presence check at all" do
    judgeable = passages.count { |passage| elsewhere_in(passage).any? }

    assert_equal 36, judgeable,
                 "the judgeable set changed -- re-read Story::Audit finding 5 before shipping a presence check"
  end

  # THE NUMERATOR, and it is the second half: one passage in 248 even names the
  # absent person, so there is no false-positive RATE to report. A check whose
  # whole measurement is n = 1 fails EVALUATION.md's point 2 however clean that
  # one flag is.
  test "exactly one frozen passage names somebody the records place in another room" do
    named = passages.select do |passage|
      elsewhere_in(passage).any? { |fullname| names?(passage.text, fullname) }
    end

    assert_equal 1, named.size, "a second judgeable naming appeared -- the measurement in finding 5 is stale"
    assert_includes named.sole.text, DEMONSTRATED_POSITIVE
    assert_equal "The Long Hallway", named.sole.room
  end

  # AND THE ZERO IS AN ARTIFACT OF THE PLACEMENT, not a property of the check.
  # Grenn Ollivar is in Room 3 in the file, and the narration corpus is 24 Room
  # 3 passages, so none of it is judgeable. Put him one door away -- the
  # hallway, where a landlord plausibly is, and an authoring choice rather than
  # a defect -- and real, correct prose starts contradicting the records.
  test "moving one seeded character one door makes real prose read as a violation" do
    seeded_whereabouts["The Lunar Cartographer"]["Grenn Ollivar"] = "Grenn's Boarding House hallway"

    judgeable = passages.select { |passage| elsewhere_in(passage).any? }
    assert_operator judgeable.size, :>, 36, "the sensitivity run should widen the judgeable set"

    CORRECT_PROSE_ABOUT_SOMEBODY_ELSEWHERE.each do |sentence|
      passage = judgeable.find { |candidate| candidate.text.include?(sentence) }

      assert passage, "#{sentence.inspect} is no longer in a judgeable passage"
      assert names?(passage.text, "Grenn Ollivar"),
             "#{sentence.inspect} names Grenn, is correct prose about a man in another room, and is what any " \
             "name-based presence check would flag. See Story::Audit finding 5."
    end
  end

  # AND THE ENGINE COVERS THE GAP FROM THE OTHER SIDE, which is the reason not
  # shipping the check costs less than it looks. Prose may name somebody who is
  # elsewhere; the player still cannot SPEAK to them, because
  # `Character.present_in` is the closed set the classifier resolves a `talk`
  # against and nothing about the prose widens it.
  test "the closed set talk resolves against does not include somebody recorded elsewhere" do
    story = create(:story)
    here = create(:location, story: story, name: "Ward Office 12")
    there = create(:location, story: story, name: "The Long Hallway")
    protagonist = create(:character, :protagonist, story: story)
    rowe = create(:character, story: story, fullname: "Halkett Rowe", location: there)

    playthrough = create(:playthrough, story: story, character: protagonist, current_location: here)

    assert_equal [], Playthrough::Classifier.new(playthrough).characters_here
    assert_equal [ protagonist ], Scene::Generator.characters_present(here)
    assert_equal [ rowe ], Character.present_in(there).to_a
  end
end
