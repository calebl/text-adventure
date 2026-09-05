require "test_helper"

# THE FIXED GRAMMAR ON ITS OWN, and in particular the two questions it grew on
# the captain's ruling of 2026-09-04, evening: WHICH LINES IT CLAIMS, and which
# reader it says answered.
#
# Everything below runs with no model at all -- `Playthrough::Grammar` makes no
# call, ever, and `EngineSweep.without_a_model` is the assertion of that rather
# than a hope. What it reads is the same closed sets `Playthrough::Classifier`
# offers a model, so the world here is shaped like a room somebody is standing
# in with a way out, a person, something on the floor and something in hand.
class Playthrough::GrammarTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @vance = create(:character, story: @story, fullname: "Odile Vance", is_protagonist: true)
    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
    create(:location_connection, location: @office, connected_location: @closet,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: @closet, connected_location: @office,
                                 distance: "adjacent", travel_method: "walking")

    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", nickname: "Rowe", location: @office)
    @playthrough = create(:playthrough, story: @story, character: @vance, current_location: @office)
    @stamp = create(:item, :lying, playthrough: @playthrough, location: @office, name: "ward stamp")
    @daybook = create(:item, :carried, playthrough: @playthrough, name: "Ward Office 12 daybook")
  end

  def grammar = Playthrough::Grammar.new(@playthrough)

  def read(line)
    EngineSweep.without_a_model { grammar.reading_first(line) }
  end

  # --- the slash ------------------------------------------------------------

  test "the slash is input syntax and is taken off the front" do
    assert_equal "take slate", Playthrough::Grammar.unslashed("/take slate")
    assert_equal "take slate", Playthrough::Grammar.unslashed("  /take slate  ")
    assert_equal "take slate", Playthrough::Grammar.unslashed("take slate")
    # Only the front, and only one: a slash inside a line is part of the line.
    assert_equal "read the s/v ledger", Playthrough::Grammar.unslashed("read the s/v ledger")
    assert_equal "/take slate", Playthrough::Grammar.unslashed("//take slate")
  end

  test "a slashed line is claimed even when the grammar cannot read the verb" do
    reading = read("/frobnicate the stamp")

    assert_not_nil reading, "a slashed line is always the grammar's to read first"
    assert_not_predicate reading, :resolved?
    assert_includes reading.refusal, "I do not understand"
  end

  # --- what is claimed and what is left alone -------------------------------

  test "the slash is the whole of the claim, and every synonym works behind one" do
    Playthrough::Grammar::VERBS.each_key do |verb|
      assert grammar.claims?("/#{verb} something"), "/#{verb} should be claimed"
    end
    assert grammar.claims?("/anything at all")
  end

  # THE CAPTAIN'S RULING OF 2026-09-05: *"I think we should only auto accept the
  # slash commands."* A leading verb is a coincidence of English, and nothing but
  # a slash says "read this as a command".
  test "no unslashed line is claimed, whatever it begins with" do
    [ "hello", "what about that key then", "wait", "north",
      "go to the supply closet", "take the ward stamp", "talk to Rowe",
      "drop the daybook", "read the ward stamp", "look at the sky" ].each do |line|
      assert_nil read(line), "#{line.inspect} should be left to the classifier"
    end
  end

  # THE FOUR THAT MADE THE RULING, and each one is a real record answered on an
  # ordinary English line that meant something else. They are pinned here so the
  # verb-prefixed claim cannot come back without somebody reading this.
  test "the lines a leading verb alone would have answered wrongly" do
    tavern = create(:location, story: @story, name: "The Bell and Anchor")
    create(:location_connection, location: @office, connected_location: tavern,
                                 distance: "adjacent", travel_method: "walking")

    [ "move the supply closet shelf aside",
      "walk the supply closet perimeter",
      "leave the ward office",
      "take a look at the ward stamp" ].each do |line|
      assert_nil read(line), "#{line.inspect} must reach the classifier"
    end
  end

  # THE ENGINE'S OWN INSTRUMENTS ARE NOT CLAIMED IN THE BROWSER. They are
  # `Playthrough::Mechanics`'s, and a player typing `stats` at the fiction has
  # always reached the classifier.
  test "an engine-view verb is not claimed" do
    [ "stats", "vitals", "harm 5", "mend 2", "check strength", "help" ].each do |line|
      assert_nil read(line), "#{line.inspect} is an engine-view verb and not the browser's grammar to read"
    end
  end

  # --- what it resolves -----------------------------------------------------

  test "each of the five verbs resolves out of the set its action reads against" do
    assert_equal @closet, read("/go to the supply closet").intent.destination
    assert_equal @rowe, read("/talk to Rowe").intent.speaker
    assert_equal @stamp, read("/take the ward stamp").intent.item
    assert_equal @daybook, read("/drop the daybook").intent.item
    assert_equal @stamp, read("/read the ward stamp").intent.item
  end

  # THE SLASH IS STRIPPED BEFORE THE LINE IS READ, so what the grammar answers
  # behind one is exactly what `#parse` answers without one. The ROUTER differs
  # -- only the slashed form is claimed at all -- and that is `#claims?`'s job,
  # not the parser's.
  test "the slash is taken off before the line is parsed" do
    [ "go to the supply closet", "talk to Rowe", "take the ward stamp",
      "drop the daybook", "read the ward stamp" ].each do |line|
      plain = EngineSweep.without_a_model { grammar.parse(line) }
      slashed = read("/#{line}")

      assert_equal plain.intent.action, slashed.intent.action
      assert_equal plain.intent.subject, slashed.intent.subject
      assert_equal "grammar", slashed.resolved_by
    end
  end

  # A `take` reads the floor and a `drop` reads the hands, and the grammar is
  # under exactly the rule the classifier is: neither ever answers out of the
  # other's set.
  test "a verb does not resolve out of another verb's closed set" do
    assert_not_predicate read("/take the daybook"), :resolved?
    assert_not_predicate read("/drop the ward stamp"), :resolved?
    assert_not_predicate read("/go to Rowe"), :resolved?
  end

  test "a name that lands on nothing is a refusal and never a record" do
    reading = read("/take the crown")

    assert_not_predicate reading, :resolved?
    assert_includes reading.refusal, "there is no thing lying here"
  end

  test "an ambiguous name is refused rather than guessed at" do
    create(:item, :lying, playthrough: @playthrough, location: @office, name: "ward register")
    reading = read("/take the ward")

    assert_not_predicate reading, :resolved?
    assert_includes reading.refusal, "matches more than one"
  end

  # --- the line it will not answer even though it could ---------------------

  # THE ONE THING THAT MAKES THE GRAMMAR HAND BACK A LINE IT RESOLVED. It has no
  # `also_named`, so a line naming two things out of one closed set would resolve
  # the first and PLAY it, where `Playthrough::Classifier` sees both and the line
  # is refused -- the captain's ruling of 2026-09-04, one line one act. Measured
  # on `Eval::Classifier`'s 300 labelled lines: 6 wrong answers, all six this shape.
  test "a line that joins two things is not answered offline" do
    apron = create(:item, :lying, playthrough: @playthrough, location: @office, name: "copy-room apron")
    # A SHORT SECOND NAME, which is the shape the guard is for: two names in FULL
    # already match more than one record and were refused by the ambiguity rule
    # long before any of this. "the apron" matches nothing on its own, so the
    # line resolves cleanly to the stamp -- and playing it would be playing half
    # a line.
    reading = read("/take the ward stamp and the apron")

    assert_not_predicate reading, :resolved?
    assert_equal Playthrough::Grammar::MORE_THAN_ONE_ACT, reading.refusal
    assert_equal @office, apron.reload.location
  end

  test "two names in full were already refused, by the ambiguity rule" do
    create(:item, :lying, playthrough: @playthrough, location: @office, name: "copy-room apron")
    reading = read("/take the ward stamp and the copy-room apron")

    assert_not_predicate reading, :resolved?
    assert_includes reading.refusal, "matches more than one"
  end

  test "then and a comma join two acts as surely as and does" do
    assert_not_predicate read("/go to the supply closet and then back"), :resolved?
    assert_not_predicate read("/take the ward stamp, then read it"), :resolved?
  end

  # THE NAME ITSELF IS CUT OUT FIRST, so a record whose own name carries a
  # joining word is not a second act. Without that, a world with a room called
  # "The Bell and Anchor" would never resolve a move offline.
  test "a joining word inside the name a line resolved to is part of the name" do
    tavern = create(:location, story: @story, name: "The Bell and Anchor")
    create(:location_connection, location: @office, connected_location: tavern,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: tavern, connected_location: @office,
                                 distance: "adjacent", travel_method: "walking")

    assert_equal tavern, read("/go to The Bell and Anchor").intent.destination
  end

  # THE GUARD IS ABOUT DEFERRING TO A MODEL, and `#parse` has none to defer to:
  # `rake game:sweep` and `Eval::Classifier::Offline` both reach it directly and
  # must still get an answer. So the offline floor is byte-identical across this
  # change, which is the property the bench's stored sets depend on.
  test "the offline parse still answers a joined line, because nothing is behind it" do
    create(:item, :lying, playthrough: @playthrough, location: @office, name: "copy-room apron")
    reading = EngineSweep.without_a_model { grammar.parse("take the ward stamp and the apron") }

    assert_predicate reading, :resolved?
    assert_equal @stamp, reading.intent.item
  end

  # --- which reader answered ------------------------------------------------

  test "the parse says which reader answered" do
    assert_equal "grammar", grammar.parse("take the ward stamp").resolved_by
    assert_equal "grammar", grammar.parse("look").resolved_by
    assert_equal "engine_view", grammar.parse("stats").resolved_by
    assert_equal "engine_view", grammar.parse("harm 3").resolved_by
    assert_equal "engine_view", grammar.parse("check strength").resolved_by
    assert_equal "engine_view", grammar.parse("help").resolved_by
  end

  test "the closed list of readers is the one every consumer reads" do
    assert_equal %w[grammar model engine_view], Playthrough::Grammar::PATHS
    assert_equal %w[grammar model], Scene::TURN_READERS
  end

  # The menu offers five words, and every one of them is a word the grammar
  # reads -- so the box cannot complete to something the engine will not answer.
  test "the five offered verbs are all in the grammar's own table" do
    assert_equal %w[go talk take drop read], Playthrough::Grammar::RESOLVING.keys

    Playthrough::Grammar::RESOLVING.each do |word, action|
      assert_includes Playthrough::Grammar::VERBS.keys, word
      assert_predicate read("/#{word}"), :present?, "/#{word} should be claimed"
      assert_equal action, Playthrough::Classifier::Intent.new(action: action).action
    end
  end
end
