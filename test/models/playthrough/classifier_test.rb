require "test_helper"

# The classifier is one model call, and everything either side of it is the
# part worth testing: what candidates the model is offered, and what its answer
# resolves back to. Both directions have to agree -- a name the prompt did not
# offer cannot resolve, and a name that resolves to nothing has to leave the
# loop free to narrate a failure instead of moving the player somewhere.
#
# Never a live model: FakeAgent stands in at the BaseAgent boundary.
class Playthrough::ClassifierTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
  end

  def classify(answer, command: "go on then")
    agent = FakeAgent.new(answer)
    intent = BaseAgent.stub(:new, agent) do
      Playthrough::Classifier.new(@playthrough).classify(command)
    end

    [ intent, agent ]
  end

  def connect(name, distance: "adjacent", travel_method: "walking", **attributes)
    neighbour = create(:location, story: @story, name: name, **attributes)
    create(:location_connection, location: @here, connected_location: neighbour,
                                 distance: distance, travel_method: travel_method)
    neighbour
  end

  # --- resolving a move ----------------------------------------------------

  test "a move resolves to the exit record the player named" do
    stair = connect("The Sunken Stair")

    intent, = classify({ "intent" => "move", "target" => "The Sunken Stair" })

    assert intent.move?
    assert_equal stair, intent.destination
    assert_nil intent.speaker
  end

  test "an exit is resolved by name regardless of case" do
    stair = connect("The Sunken Stair")

    intent, = classify({ "intent" => "move", "target" => "the sunken stair" })

    assert_equal stair, intent.destination
  end

  # A stub is exactly what the player is meant to be able to walk into: it is
  # only realized because they chose it.
  test "a stub exit is a legitimate destination" do
    vestibule = connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    intent, = classify({ "intent" => "move", "target" => "Drowned Vestibule" })

    assert_equal vestibule, intent.destination
    assert_predicate vestibule, :stub?
  end

  # The point of the closed enum. If a name does get through that resolves to
  # nothing, the loop must fall through to narration rather than guess.
  test "a move nobody can make resolves to no destination" do
    connect("The Sunken Stair")

    intent, = classify({ "intent" => "move", "target" => "nothing" })

    assert intent.move?
    assert_nil intent.destination
  end

  test "a place that is not an exit from here resolves to no destination" do
    create(:location, story: @story, name: "Somewhere Else Entirely")

    intent, = classify({ "intent" => "move", "target" => "Somewhere Else Entirely" })

    assert_nil intent.destination
  end

  # --- resolving a talk ----------------------------------------------------

  test "a talk resolves to the character standing here" do
    maren = holdover("Maren Vosk", nickname: "Maren")

    intent, = classify({ "intent" => "talk", "target" => "Maren Vosk" })

    assert intent.talk?
    assert_equal maren, intent.speaker
    assert_nil intent.destination
  end

  # A player types the name they were shown, and an arrival paragraph calls
  # people by their nickname as often as their full name.
  test "a talk resolves by nickname too" do
    maren = holdover("Maren Vosk", nickname: "Maren")

    intent, = classify({ "intent" => "talk", "target" => "Maren" })

    assert_equal maren, intent.speaker
  end

  test "a talk with nobody here resolves to no speaker" do
    intent, = classify({ "intent" => "talk", "target" => "nothing" })

    assert intent.talk?
    assert_nil intent.speaker
  end

  # --- the other three -----------------------------------------------------

  test "examine, take and other carry no target" do
    connect("The Sunken Stair")
    holdover("Maren Vosk")

    %w[examine take other].each do |action|
      intent, = classify({ "intent" => action, "target" => "The Sunken Stair" })

      assert_equal action.to_sym, intent.action
      assert_nil intent.destination
      assert_nil intent.speaker
    end
  end

  # A model that answers outside its own enum is the failure BaseAgent exists to
  # distrust. Treating it as `other` narrates the turn, which is the safe
  # outcome; treating it as a move would send the player somewhere on a typo.
  test "an intent outside the fixed set becomes other" do
    intent, = classify({ "intent" => "wander vaguely", "target" => "nothing" })

    assert_equal :other, intent.action
  end

  # --- the candidates the model is offered ---------------------------------

  test "the target enum is exactly the exits and the people here" do
    connect("The Sunken Stair")
    holdover("Maren Vosk", nickname: "Maren")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    enum = agent.schemas.last.new.to_json_schema.dig(:schema, :properties, :target, :enum)
    assert_equal [ "The Sunken Stair", "Maren Vosk", "Maren", "nothing" ], enum
  end

  test "the prompt names the room, its exits and who is in it" do
    connect("The Sunken Stair", distance: "adjacent", travel_method: "taking stairs")
    holdover("Maren Vosk", nickname: "Maren")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" }, command: "look around")
    prompt = agent.prompts.first

    assert_match(/Ashgate Market/, prompt)
    assert_match(/- The Sunken Stair \(adjacent, taking stairs\)/, prompt)
    assert_match(/- Maren Vosk \(Maren\)/, prompt)
    assert_match(/look around/, prompt)
  end

  # The player is not somebody to talk to, and offering them as a candidate is
  # how "talk to myself" becomes a resolvable move.
  test "the protagonist is not offered as somebody to talk to" do
    holdover("Maren Vosk")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_no_match(/Iri Calder/, agent.prompts.first)
  end

  # Not decoration: a room with no way out and nobody in it is a real state
  # (`Location::Generator` can leave a room short of its exits), and the prompt
  # has to say so rather than showing the model two empty headings.
  test "an empty room says so in words" do
    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })
    prompt = agent.prompts.first

    assert_match(/cannot go anywhere/, prompt)
    assert_match(/no one here to talk to/, prompt)
  end

  test "the instructions tell the model not to narrate" do
    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_match(/do not narrate/i, agent.instructions)
  end

  # --- who counts as present ------------------------------------------------

  # One list, decided in one place. Scene::Generator writes the cast onto the
  # arrival scene; this reads that same answer back, so the classifier accepts
  # exactly the people the arrival paragraph introduced.
  test "the cast is Scene::Generator's answer, minus the player" do
    maren = holdover("Maren Vosk")
    companion = create(:character, story: @story, fullname: "Dell Roy", is_companion: true)

    cast = Playthrough::Classifier.new(@playthrough).characters_here

    assert_equal [ maren, companion ].sort_by(&:id), cast.sort_by(&:id)
    assert_not_includes cast, @protagonist
  end

  test "a playthrough that is nowhere offers nothing to aim at" do
    adrift = create(:playthrough, story: @story, character: @protagonist)

    classifier = Playthrough::Classifier.new(adrift)

    assert_empty classifier.exits_here
    assert_empty classifier.characters_here
  end

  private

  # Somebody the game knows is standing here: recorded in the last scene played
  # in this location, which is how Scene::Generator answers the question.
  def holdover(fullname, **attributes)
    character = create(:character, story: @story, fullname: fullname, **attributes)
    create(:scene, story: @story, location: @here, characters: [ character ])
    character
  end
end
