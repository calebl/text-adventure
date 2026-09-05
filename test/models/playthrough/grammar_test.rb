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
    assert_equal @stamp, read("/inspect the ward stamp").intent.item
  end

  # THE MENU'S WORD CHANGED AND THE VERB DID NOT. `inspect` is what the box
  # offers after a `/` since the captain's ruling of 2026-09-05; `read` and
  # every other synonym still resolve exactly the same intent on the same row.
  test "inspect and read are one verb" do
    inspected = read("/inspect the ward stamp")
    was_read = read("/read the ward stamp")

    assert_equal :examine, inspected.intent.action
    assert_equal was_read.intent.action, inspected.intent.action
    assert_equal @stamp, inspected.intent.item
    assert_equal was_read.intent.item, inspected.intent.item
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

  # --- attack ---------------------------------------------------------------

  # THE CAPTAIN'S SIXTH RULING OF 2026-09-05: *"anyone can be attacked"*. The
  # verb resolves against the FULL present-people set -- the same one `talk`
  # reads -- because a narrower list of who may be hit would be the app deciding
  # who is a legitimate target.
  test "a slashed attack resolves anybody standing here, hostile or not" do
    reading = read("/attack Halkett Rowe")

    assert_predicate reading, :resolved?
    assert_equal :attack, reading.intent.action
    assert_equal @rowe, reading.intent.speaker
    assert_predicate reading.intent, :attack?
    assert_not_predicate @rowe, :hostile?
  end

  test "it matches a nickname and a fragment like every other name in this grammar" do
    assert_equal @rowe, read("/attack Rowe").intent.speaker
    assert_equal @rowe, read("/hit halkett").intent.speaker
    assert_equal @rowe, read("/strike Rowe").intent.speaker
  end

  test "a name nobody here answers to is refused with the cast that is here" do
    reading = read("/attack the bell")

    assert_not_predicate reading, :resolved?
    assert_includes reading.refusal, "Halkett Rowe"
  end

  test "attacking nobody in particular names who is here" do
    assert_includes read("/attack").refusal, "attack whom?"
  end

  # `engine_view` ON `scenes.resolved_by` MEANS NO SCENE COMES OF IT
  # (`Scene::TURN_READERS`), and a fight ends in one -- so a resolved attack is
  # the GRAMMAR's answer even though `attack` is in `ENGINE_VIEW`.
  test "a resolved attack is read by the grammar and not by the engine view" do
    assert_equal "grammar", read("/attack Halkett Rowe").resolved_by
    assert_equal "engine_view", EngineSweep.without_a_model { grammar.parse("stats") }.resolved_by
  end

  # THE SAME GUARD `check` HAS, for the same reason: *"attack the problem"* is
  # ordinary English, and swallowing it here would cost the mode a verb.
  test "with a model available, attack is the engine's own only when the name is somebody here" do
    EngineSweep.without_a_model do
      assert_not_nil grammar.engine_view_reading("attack Halkett Rowe", model: true)
      assert_nil grammar.engine_view_reading("attack the problem", model: true)
      # With no model there is nothing to hand it to, so the grammar answers and
      # refuses.
      assert_not_nil grammar.engine_view_reading("attack the problem", model: false)
    end
  end

  test "an unslashed attack is not claimed at all, whatever it begins with" do
    assert_nil read("attack Halkett Rowe")
  end

  test "the closed list of readers is the one every consumer reads" do
    assert_equal %w[grammar model engine_view], Playthrough::Grammar::PATHS
    assert_equal %w[grammar model], Scene::TURN_READERS
  end

  # --- a throw, which is the one line that names two records ----------------

  test "a slashed throw resolves the thing and the aim out of two closed sets" do
    reading = read("/throw the daybook at Halkett Rowe")

    assert_predicate reading, :resolved?
    assert_equal :throw, reading.intent.action
    assert_equal @daybook, reading.intent.item
    assert_equal @rowe, reading.intent.at
    assert_equal "throw -> Ward Office 12 daybook at Halkett Rowe", reading.understood
    assert_equal "grammar", reading.resolved_by
  end

  # THE THING COMES OUT OF BOTH ITEM SETS, which is the captain's own words --
  # *"pick up items and throw them"* -- and `data/ta-combat-scout` §13.3's *"the
  # lift IS the throw"*. A thing on the floor needs no `take` first.
  test "a throw reads a thing off the floor as readily as one in your hands" do
    reading = read("/throw the ward stamp at Rowe")

    assert_predicate reading, :resolved?
    assert_equal @stamp, reading.intent.item
    assert_equal @rowe, reading.intent.at
  end

  test "a throw can be aimed through one of the ways out" do
    reading = read("/throw the daybook at the supply closet")

    assert_equal @closet, reading.intent.at
    assert_equal @daybook, reading.intent.item
  end

  test "hurl and toss are the same verb" do
    %w[hurl toss].each do |word|
      assert_equal :throw, read("/#{word} the daybook at Rowe").intent.action
    end
  end

  # THE FIRST STANDALONE `at` SPLITS THE LINE, and word boundaries keep a hat
  # and a tally out of it.
  test "at is matched on word boundaries and the first one splits the line" do
    hat = create(:item, :lying, playthrough: @playthrough, location: @office, name: "flat hat")

    assert_equal hat, read("/throw the flat hat at Rowe").intent.item
    assert_equal @rowe, read("/throw the flat hat at Rowe").intent.at
  end

  test "a throw with no argument names what there is to throw" do
    reading = read("/throw")

    assert_not_predicate reading, :resolved?
    assert_match(/throw what at what\?/, reading.refusal)
    assert_match(/ward stamp/, reading.refusal)
    assert_match(/Ward Office 12 daybook/, reading.refusal)
  end

  test "a throw with no aim names both aim sets, because they are two mistakes" do
    reading = read("/throw the daybook")

    assert_not_predicate reading, :resolved?
    assert_match(/at what\?/, reading.refusal)
    assert_match(/Here with you: Halkett Rowe/, reading.refusal)
    assert_match(/The ways out are: The Supply Closet/, reading.refusal)
  end

  test "a thing that is neither carried nor lying here is refused" do
    reading = read("/throw the tide-slate at Rowe")

    assert_not_predicate reading, :resolved?
    assert_match(/no thing in your hands or lying here/, reading.refusal)
  end

  # AMBIGUITY AND ABSENCE ARE TOLD APART, which is this grammar's rule
  # everywhere else too: one is a name that was too short, the other a name for
  # something that is not there.
  test "an aim that lands on two things is refused as ambiguous" do
    create(:location_connection, location: @office,
                                 connected_location: create(:location, story: @story, name: "The Supply Room"),
                                 distance: "adjacent", travel_method: "walking")

    reading = read("/throw the daybook at the supply")

    assert_not_predicate reading, :resolved?
    assert_match(/matches more than one thing to throw it at/, reading.refusal)
    assert_match(/The Supply Closet/, reading.refusal)
  end

  test "an aim that is neither somebody here nor a way out is refused" do
    reading = read("/throw the daybook at the moon")

    assert_not_predicate reading, :resolved?
    assert_match(/nothing called "the moon" to throw it at/, reading.refusal)
  end

  # BOTH OF A THROW'S NAMES COME OUT BEFORE `JOINING_WORDS` IS LOOKED FOR, or a
  # room called "The Bell and Anchor" would read as a second act.
  test "a room whose own name joins two words is not a second act" do
    bell = create(:location, story: @story, name: "The Bell and Anchor")
    create(:location_connection, location: @office, connected_location: bell,
                                 distance: "adjacent", travel_method: "walking")

    reading = read("/throw the daybook at the bell and anchor")

    assert_predicate reading, :resolved?
    assert_equal bell, reading.intent.at
  end

  test "a throw that really joins two acts is handed to the model" do
    reading = read("/throw the daybook at Rowe and take the stamp")

    assert_not_predicate reading, :resolved?
    assert_equal Playthrough::Grammar::MORE_THAN_ONE_ACT, reading.refusal
  end

  # `throw` IS ORDINARY ENGLISH, so with a model available it is the engine's
  # own only when BOTH halves land -- *"throw the switch"* and *"throw a party"*
  # reach the classifier exactly as they always did.
  test "throw is the engine's own only when the line names two records" do
    EngineSweep.without_a_model do
      assert_not_nil grammar.engine_view_reading("throw the daybook at Halkett Rowe", model: true)
      assert_nil grammar.engine_view_reading("throw the switch", model: true)
      assert_nil grammar.engine_view_reading("throw a party", model: true)
      # With no model there is nothing to hand it to, so the grammar answers.
      assert_not_nil grammar.engine_view_reading("throw the switch", model: false)
    end
  end

  test "an unslashed throw is not claimed at all" do
    assert_nil read("throw the daybook at Halkett Rowe")
  end

  # A THROW IS DELIBERATELY NOT IN `RESOLVING`, and that is a statement about
  # the list's SHAPE: it maps one word to ONE action so `Playthrough::SlashMenu`
  # can put one closed set under it, and a throw names two records out of two
  # sets. The verb still works behind a slash, which is what the cases above
  # walk.
  test "throw is not offered as a slash completion, and still reads behind one" do
    assert_not_includes Playthrough::Grammar::RESOLVING.keys, "throw"
    assert_includes Playthrough::Grammar::VERBS.keys, "throw"
    assert_predicate read("/throw the daybook at Rowe"), :resolved?
  end

  # The menu offers six words, and every one of them is a word the grammar
  # reads -- so the box cannot complete to something the engine will not answer.
  test "the six offered verbs are all in the grammar's own table" do
    assert_equal %w[go talk take drop inspect attack], Playthrough::Grammar::RESOLVING.keys

    Playthrough::Grammar::RESOLVING.each do |word, action|
      assert_includes Playthrough::Grammar::VERBS.keys, word
      assert_predicate read("/#{word}"), :present?, "/#{word} should be claimed"
      assert_equal action, Playthrough::Classifier::Intent.new(action: action).action
    end
  end
end
