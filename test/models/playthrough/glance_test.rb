require "test_helper"

# THE PANELS AND THE VERBS, read off records with no model anywhere. Every test
# runs with `BaseAgent.new` raising, so a reader that reached for a model fails
# on the spot rather than passing quietly.
class Playthrough::GlanceTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @vance = create(:character, story: @story, fullname: "Odile Vance", is_protagonist: true)
    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
    @hallway = create(:location, :stub, story: @story, name: "The Long Hallway")
    connect(@office, @closet)
    connect(@office, @hallway)
    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", location: @office)
    @playthrough = create(:playthrough, story: @story, character: @vance, current_location: @office)
    @stamp = lying_here(@playthrough, @office, name: "ward stamp")
    @press = lying_here(@playthrough, @office, :immovable, name: "filing press")
    @daybook = create(:item, :carried, playthrough: @playthrough, name: "Ward Office 12 daybook")
  end

  def connect(from, to, **edge)
    create(:location_connection, location: from, connected_location: to, distance: "adjacent", travel_method: "walking", **edge)
    create(:location_connection, location: to, connected_location: from, distance: "adjacent", travel_method: "walking", **edge)
  end

  def offline(&block) = BaseAgent.stub(:new, ->(*) { raise "the glance made a model call" }, &block)
  def glance = offline { Playthrough::Glance.new(@playthrough.reload) }
  def verb(name) = offline { Playthrough::Availability.new(@playthrough.reload).verb(name) }

  # --- the panels -----------------------------------------------------------

  test "the room panel names the room and each way out, written or not" do
    g = glance
    assert_equal @office, g.location
    exits = g.exits.to_h { |exit| [ exit.name, exit.written ] }
    assert_equal({ "The Supply Closet" => true, "The Long Hallway" => false }, exits)
    assert g.exits.all?(&:open)
  end

  test "the people, items and inventory panels are the records" do
    g = glance
    assert_equal [ "Halkett Rowe" ], g.people.map(&:name)
    assert_not g.people.first.foe
    assert_equal [ @stamp, @press ], g.items_here
    assert_equal [ @daybook ], g.carried
  end

  test "a foe is marked as one on the people panel" do
    @rowe.update!(hostile: true)
    assert glance.people.first.foe
  end

  test "the condition panel is the player's own" do
    assert_equal @playthrough.condition&.in_words, glance.condition&.in_words
    assert_not glance.over?
    assert_nil glance.ended
  end

  test "an arc-less world has no next beat" do
    assert_nil glance.next_beat
    assert_includes glance.to_s, "this world has no arc"
  end

  test "the next beat is the summary the narrator is told" do
    quest = create(:quest, story: @story)
    create(:quest_step, quest: quest, summary: "Find where they are keeping him.")
    assert_equal "Find where they are keeping him.", glance.next_beat
    assert_equal Playthrough::Moment.new(@playthrough.reload).send(:next_beat), glance.next_beat
  end

  test "the session answers the glance and the read-out makes no model call" do
    text = offline { Playthrough::Session.new(@playthrough).glance.to_s }
    assert_includes text, "Ward Office 12"
    assert_includes text, "The Long Hallway [unwritten]"
    assert_match(/take\s+ward stamp$/, text)
  end

  # --- the verbs ------------------------------------------------------------

  test "every verb in the closed set is answered" do
    names = offline { Playthrough::Availability.new(@playthrough).verbs.map(&:name) }
    assert_equal Playthrough::IntentSchema::INTENTS.map(&:to_sym) - [ :other ], names.sort_by { |n| Playthrough::IntentSchema::INTENTS.index(n.to_s) }
  end

  test "move offers the ways out" do
    assert_equal [ @closet, @hallway ], verb(:move).targets
  end

  test "a shut way out is not offered to move or to a throw, and reads as shut" do
    LocationConnection.where(location: @office, connected_location: @closet).update_all(barrier: "jammed")
    assert_equal [ @hallway ], verb(:move).targets
    assert_not_includes verb(:throw).aims, @closet
    assert_not glance.exits.find { |exit| exit.location == @closet }.open
  end

  test "an immovable thing is not offered to take or throw, and is still offered to examine" do
    assert_equal [ @stamp ], verb(:take).targets
    assert_not_includes verb(:throw).targets, @press
    assert_includes verb(:examine).targets, @press
  end

  test "talk and attack offer who is standing here" do
    assert_equal [ @rowe ], verb(:talk).targets
    assert_equal [ @rowe ], verb(:attack).targets
  end

  test "the dead are offered to nobody and stand on no panel" do
    @playthrough.vitals.find_by!(character: @rowe).update!(hp_current: 0)
    assert_empty glance.people
    assert_not verb(:talk).available?
    assert_equal Playthrough::Refusal::EMPTY[:talk], verb(:talk).reason
    assert_equal Playthrough::Refusal::EMPTY[:attack], verb(:attack).reason
    assert_not_includes verb(:throw).aims, @rowe
  end

  test "a fight in progress keeps the foe as a target of attack and throw" do
    @rowe.update!(hostile: true)
    Playthrough::Turn.new(@playthrough).harm!(@rowe, 1)
    assert_includes verb(:attack).targets, @rowe
    assert_includes verb(:throw).aims, @rowe
    assert glance.people.first.foe
  end

  test "drop offers what is carried and throw offers both item sets" do
    assert_equal [ @daybook ], verb(:drop).targets
    assert_equal [ @daybook, @stamp ], verb(:throw).targets
  end

  test "an empty room blocks every verb that needs something here, with the engine's words" do
    bare = create(:location, story: @story, name: "A Bare Cell")
    game = create(:playthrough, story: @story, character: @vance, current_location: bare)
    availability = offline { Playthrough::Availability.new(game) }
    %i[move talk take drop attack use].each do |name|
      verb = availability.verb(name)
      assert_not verb.available?, name
      assert_empty verb.targets, name
      assert_equal Playthrough::Refusal::EMPTY[name], verb.reason, name
    end
    assert_equal Playthrough::Availability::REASONS[:examine], availability.verb(:examine).reason
    assert_equal Playthrough::Availability::REASONS[:throw], availability.verb(:throw).reason
  end

  test "a game with no player character cannot take or throw, and says why" do
    @playthrough.update!(character: nil)
    reason = verb(:take).reason
    assert_includes reason, Playthrough::Refusal::NO_PROTAGONIST[:take]
    assert_includes verb(:throw).reason, Playthrough::Refusal::NO_PROTAGONIST[:throw]
  end

  test "a finished game blocks every verb with the end notice's sentence" do
    @playthrough.vitals.find_by!(character: @vance).update!(hp_current: 0)
    @playthrough.update!(ended_at: Time.current)
    sentence = Playthrough::EndNotice.for(@playthrough).sentence
    verbs = offline { Playthrough::Availability.new(@playthrough.reload).verbs }
    verbs.each do |verb|
      assert_not verb.available?, verb.name
      assert_empty verb.targets, verb.name
      assert_equal sentence, verb.reason
    end
    assert_equal sentence, glance.ended
  end

  test "use offers the closed physical attempts" do
    water = create(:item, :carried, playthrough: @playthrough, name: "flask of water", use_kind: "drink")
    tokens = verb(:use).targets.map(&:token)
    assert_includes tokens, Playthrough::PhysicalAction::Choice.new(kind: "consume", item: water).token
  end

  test "each verb's word is the grammar's own, and use has none of its own" do
    words = Playthrough::Availability::VERBS.to_h { |name| [ name, Playthrough::Grammar.word_for(name) ] }
    assert_equal({ move: "go", talk: "talk", examine: "inspect", take: "take", drop: "drop",
                   attack: "attack", throw: "throw", use: nil }, words)
    words.compact.each_value { |word| assert Playthrough::Grammar::VERBS.key?(word), word }
  end

  test "the line given for each use target is read back as that very target" do
    LocationConnection.where(location: @office, connected_location: @closet).update_all(barrier: "jammed")
    create(:item, :carried, playthrough: @playthrough, name: "flask of water", use_kind: "drink")
    g = glance
    targets = offline { g.verb(:use).targets }
    assert_operator targets.map(&:kind).uniq.size, :>=, 3, targets.map(&:kind).inspect
    grammar = Playthrough::Grammar.new(@playthrough)
    targets.each do |choice|
      line = offline { g.line_for(choice) }
      assert_not_nil line, choice.name
      assert line.start_with?("/#{choice.kind} "), line
      assert_equal choice, offline { grammar.reading_first(line) }.intent.physical, line
    end
  end

  test "of two attempts one line cannot tell apart, only the one it plays gets it" do
    2.times { create(:item, :carried, playthrough: @playthrough, name: "flask of water", use_kind: "drink") }
    g = glance
    flasks = offline { g.verb(:use).targets }.select { |choice| choice.kind == "consume" }
    assert_equal 2, flasks.size
    lines = flasks.map { |choice| offline { g.line_for(choice) } }
    assert_equal [ "/consume flask of water" ], lines.compact
    played = offline { Playthrough::Grammar.new(@playthrough).reading_first(lines.compact.first) }.intent.physical
    assert_equal flasks[lines.index(lines.compact.first)], played
  end

  # --- the resolver and the engine agree ------------------------------------

  test "every target offered is one the engine plays" do
    @rowe.update!(hostile: true)
    LocationConnection.where(location: @office, connected_location: @closet).update_all(barrier: "jammed")
    create(:item, :carried, playthrough: @playthrough, name: "flask of water", use_kind: "drink")
    turn = Playthrough::Turn.new(@playthrough.reload)
    grammar = Playthrough::Grammar.new(@playthrough)
    slots = { move: :destination, talk: :speaker, attack: :speaker, examine: :item, take: :item, drop: :item }

    verbs = offline { Playthrough::Availability.new(@playthrough).verbs }
    verbs.each do |verb|
      verb.targets.each do |target|
        intents =
          case verb.name
          when :throw then verb.aims.map { |aim| Playthrough::Classifier::Intent.new(action: :throw, item: target, at: aim) }
          when :use then [ Playthrough::Classifier::Intent.new(action: :use, physical: target) ]
          else [ Playthrough::Classifier::Intent.new(action: verb.name, slots.fetch(verb.name) => target) ]
          end
        intents.each do |intent|
          assert_not intent.refused?, "#{verb.name} #{target.inspect}"
          assert_nil turn.refusal_for(intent, ""), "#{verb.name} #{target.inspect}"
        end
        assert_not_nil Playthrough::PhysicalAction.new(@playthrough).find(target.token) if verb.name == :use
      end
    end

    # AND THE FIXED GRAMMAR RESOLVES A SLASHED LINE NAMING EACH ONE, which is
    # the other way a target reaches the engine.
    { move: "go", talk: "talk", take: "take", drop: "drop", attack: "attack" }.each do |name, word|
      verbs.find { |v| v.name == name }.targets.each do |target|
        reading = grammar.parse("#{word} #{Playthrough::Classifier.label_for(target)}")
        assert_equal target, reading.intent&.subject, "#{word} #{target.inspect}"
      end
    end
  end
end
