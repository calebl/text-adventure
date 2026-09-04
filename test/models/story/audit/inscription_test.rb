require "test_helper"

# `inscription_misquoted`, MEASURED THE WAY EVERY OTHER CHECK HERE WAS.
#
# THE COMPLAINT BEHIND IT is the captain's, and it is the reason
# `items.inscription` exists at all. Playthrough 15, scene 77 of his own game:
# he typed *"pickup the note. what does it say?"* and the narrator answered
#
#   ...The words are hurried, as if written in haste: *"Midnight. The Bell.
#   They know about the maps."*
#
# In his words: *"when an item is a note or piece of paper, etc that has writing
# on it, we need to store that writing so it is permanently held in the game
# state."* Nothing kept those words, so the next unfolding of the same note
# could have said anything, and no check in the app could have told.
#
# THE FALSE-POSITIVE MEASUREMENT, on every corpus this project has:
#
#   367 real passages  92 hold a double-quoted span, 177 spans in total
#   92   `eval_corpus.json`       0 flags
#   24   `narration_corpus.json`  0 flags
#   132  `whole_run_corpus.json`  0 flags
#   119  `transition_corpus.json` 0 flags
#
# The gap between 177 quoted spans and 0 flags is the whole design: on a read
# turn the room still has people in it, so a check that compared quoted spans to
# an inscription would flag every line of dialogue in the game. The cue rule
# (`Story::Audit::Prose::INSCRIPTION_CUES`) is what closes it, and the two words
# measurement took OFF that list -- `says` and `writ` -- are pinned below,
# because a cue list that quietly regrows them is the check turning into the
# thing it was built not to be.
#
# THE POSITIVE CASE IS THE CAPTAIN'S OWN NARRATION, with the record put
# underneath it -- the `Story::Audit::ArrivalTest` pattern, and the strongest
# form of it available: real prose, from the turn that prompted the work.
class Story::Audit::InscriptionTest < ActiveSupport::TestCase
  Prose = Story::Audit::Prose

  # PLAYTHROUGH 15, SCENE 77, word for word. Read out of the captain's own
  # database and frozen here, because it is the only real narration in the
  # project that quotes a piece of writing.
  CAPTAINS_NOTE = <<~PROSE.strip.freeze
    You already hold the folded note in your hand, its edges slightly crumpled from where you picked it up. Unfolding it carefully, you squint at the smudged ink in the dim gaslight. The words are hurried, as if written in haste: *"Midnight. The Bell. They know about the maps."* The handwriting is unfamiliar, but the urgency in the scrawl is unmistakable. The paper trembles slightly in your grip, or perhaps that’s just the Nocturna humming through the walls, making the very air feel unstable.
  PROSE

  INVENTED = "Midnight. The Bell. They know about the maps.".freeze

  CORPORA = {
    "eval_corpus" => "text",
    "narration_corpus" => "narration",
    "whole_run_corpus" => "text",
    "transition_corpus" => "text"
  }.freeze

  def self.passages
    @passages ||= CORPORA.flat_map do |file, key|
      JSON.parse(Rails.root.join("test/fixtures/files/#{file}.json").read).map do |row|
        [ file, row["label"] || row["turn"] || row["case"], row.fetch(key) ]
      end
    end.freeze
  end

  # --- the false-positive rate ---------------------------------------------

  test "the four corpora are 367 real passages and 92 of them quote somebody" do
    assert_equal 367, self.class.passages.size
    quoting = self.class.passages.count { |(_, _, text)| text.match?(Prose::QUOTED) }

    assert_equal 92, quoting, "the corpora moved; re-measure before trusting the zero below"
  end

  test "not one of the 367 real passages reads as a quotation of something written" do
    flagged = self.class.passages.flat_map do |(file, label, text)|
      Prose.inscription_quotes(text).map { |quote| "#{file} #{label}: #{quote.text.inspect}" }
    end

    assert_equal [], flagged
  end

  # THE TWO WORDS MEASUREMENT TOOK OFF THE CUE LIST. `says` is the commonest
  # speech attribution in the corpus -- adding it raised seven flags, every one
  # dialogue. `writ` is a legal document somebody hands you in The Unrecorded
  # Hour, and it raised the one flag the list ever raised.
  test "the cue list holds neither says nor writ" do
    assert_not_includes Prose::INSCRIPTION_CUES, "says"
    assert_not_includes Prose::INSCRIPTION_CUES, "writ"
  end

  # THE SECOND RULE, MEASURED AND REJECTED: a quoted span introduced by the name
  # of the thing the turn acted on. It was the obvious way to buy recall and it
  # raised three flags over the same 367 passages, all three dialogue. Pinned as
  # a sentence the cue rule must keep refusing.
  test "the item's own name is not a cue either" do
    assert_equal [], Prose.inscription_quotes(
      'He shifts the ledger under his arm, and says, "You are standing in my light."'
    )
  end

  test "a speech attribution is not a quotation of something written" do
    assert_equal [], Prose.inscription_quotes('"You will want that writ," he says, not as suggestion but as observation.')
    assert_equal [], Prose.inscription_quotes('Grenn says, "Four pieces by moonrise. I will have it."')
  end

  # --- the reading half -----------------------------------------------------

  test "the captain's own narration reads as a quotation of something written" do
    quotes = Prose.inscription_quotes(CAPTAINS_NOTE)

    assert_equal [ INVENTED ], quotes.map(&:text)
  end

  # A quoted inscription holds its own full stops, so nothing here may be read
  # sentence by sentence -- see the note on `#inscription_quotes`.
  test "a quotation carrying three sentences is one quotation" do
    quotes = Prose.inscription_quotes('The card reads "One. Two. Three words here."')

    assert_equal [ "One. Two. Three words here." ], quotes.map(&:text)
  end

  # The cue may not step over a finished sentence to reach the next quotation.
  test "a cue cannot reach across a sentence into somebody else's line" do
    passage = 'The label is written in a careful hand. She turns to you. "Four pieces by moonrise, and I will have it."'

    assert_equal [], Prose.inscription_quotes(passage)
  end

  test "one quoted word is not a rendering of the whole inscription" do
    assert_equal [], Prose.inscription_quotes('The word inscribed there is "amended".')
  end

  # --- what counts as the same words ---------------------------------------

  test "the same words re-punctuated and re-cased are the same words" do
    assert Prose.same_written_words?("MIDNIGHT — THE BELL", "Midnight. The bell.")
  end

  test "one line quoted out of a four-line index is the same words" do
    recorded = "11 Frost — 0714/12 — closed\n2 Thaw — 0902/12 — closed\n19 Thaw — 1188/12 — QUERY RAISED"

    assert Prose.same_written_words?("19 Thaw — 1188/12 — QUERY RAISED", recorded)
  end

  test "different words are different words" do
    assert_not Prose.same_written_words?(INVENTED, "Come to the west stair before the third bell. Burn this.")
  end

  # --- the check, against real records --------------------------------------

  # THE POSITIVE CASE. The captain's real narration, over a note whose words the
  # records now hold -- and they are not the ones the paragraph quotes.
  test "the captain's turn flags once the note has words on record" do
    audit = audit_over(CAPTAINS_NOTE, inscription: "Come to the west stair before the third bell. Burn this.")
    flags = audit.flags.select { |flag| flag.code == :inscription_misquoted }

    assert_equal 1, flags.size
    assert_equal "the folded note", flags.first.evidence[:item]
    assert_equal INVENTED, flags.first.evidence["the narration says"]
  end

  # THE NEGATIVE CASE, out of the same fixture: the identical paragraph over a
  # note that really does say that. A check that fired on both would be
  # measuring the quotation marks.
  test "the same narration is clean when the record says the same words" do
    audit = audit_over(CAPTAINS_NOTE, inscription: INVENTED)

    assert_equal [], audit.flags.select { |flag| flag.code == :inscription_misquoted }
  end

  # The check reads a record, so a thing nobody has written words for cannot be
  # judged -- and is not counted in the denominator either.
  test "a readable thing with no words on record is not judged" do
    audit = audit_over(CAPTAINS_NOTE, inscription: nil)

    assert_equal [], audit.flags.select { |flag| flag.code == :inscription_misquoted }
    assert_equal 0, audit.judgeable_for(:inscription_misquoted)
  end

  # It was a `take` that produced the complaint, not an examine. Scoping this to
  # reads would have excluded the turn it was built for.
  test "a take of a readable thing is judged, because the captain's turn was one" do
    audit = audit_over(CAPTAINS_NOTE, inscription: "Burn this.", action: "take")

    assert_equal 1, audit.flags.count { |flag| flag.code == :inscription_misquoted }
    assert_equal 1, audit.judgeable_for(:inscription_misquoted)
  end

  test "a turn that acted on nothing is not judged" do
    story = world
    scene = create(:scene, story: story, location: story.locations.first,
                   description: CAPTAINS_NOTE, typed: "look around", resolved_action: "other", acted_on: nil)

    audit = Story::Audit.new(story, scenes: Scene.where(id: scene.id))

    assert_equal [], audit.flags.select { |flag| flag.code == :inscription_misquoted }
  end

  private

  def world
    @world ||= begin
      story = create(:story)
      create(:location, story: story, name: "The Boarding House Hallway")
      story
    end
  end

  def audit_over(prose, inscription:, action: "examine")
    story = world
    place = story.locations.first
    item = create(:item, :lying, name: "the folded note", location: place,
                  readable: true, inscription: inscription)
    scene = create(:scene, story: story, location: place, description: prose,
                   typed: "pickup the note. what does it say?",
                   resolved_action: action, acted_on: item)

    Story::Audit.new(story, scenes: Scene.where(id: scene.id))
  end
end
