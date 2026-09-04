require "test_helper"

# The moment the prompts are told about, built from records and nothing else.
# Three prompts read it -- the narrator, the interaction narrator and the
# character pass -- so what it says is pinned here once rather than three times.
class Playthrough::MomentTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", nickname: "Iri", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market", description: "Stalls under wet canvas.")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
  end

  def moment = Playthrough::Moment.new(@playthrough)

  def connect(name)
    neighbour = create(:location, story: @story, name: name)
    create(:location_connection, location: @here, connected_location: neighbour,
                                 distance: "adjacent", travel_method: "walking")
    neighbour
  end

  # Somebody the records put in this room -- `Character.present_in`, the closed
  # set `talk` resolves against. The scene is still written because several of
  # these tests read the last turn; the cast on it is no longer what puts
  # anybody in the room.
  def stands_here(fullname, nickname: nil)
    character = create(:character, story: @story, fullname: fullname, nickname: nickname, location: @here)
    scene = create(:scene, story: @story, location: @here, characters: [ character ],
                           typed: "shake the rain off my coat",
                           summary: "The player came in out of the rain.")
    @playthrough.update!(current_scene: scene)
    character
  end

  # --- the narrator's moment -----------------------------------------------

  # THE CLOSED SETS THE CLASSIFIER ALREADY COMPUTES, finally handed to the
  # prose. The narrator's instructions always said not to invent an exit the
  # player had not been told about; this is what tells it which exits those are.
  test "the narration context lists the ways out" do
    connect("The Sunken Stair")
    connect("Cooper's Row")

    context = moment.narration_context

    assert_match(/Ways out of here: The Sunken Stair, Cooper's Row\. There are no others\./, context)
  end

  test "the narration context lists who else is here, by name" do
    stands_here("Maren Vosk", nickname: "Maren")

    assert_match(/Also here: Maren Vosk \(Maren\)\. Nobody else is present\./, moment.narration_context)
  end

  test "the player is not listed among the people also here" do
    stands_here("Maren Vosk")

    assert_no_match(/Also here:.*Iri Calder/, moment.narration_context)
    assert_match(/The player is Iri Calder\./, moment.narration_context)
  end

  test "the narration context lists what the player is carrying" do
    create(:item, character: @protagonist, name: "Brass Key")
    create(:item, character: @protagonist, name: "Theodolite")
    create(:item, :lying, location: @here, name: "Ledger")

    context = moment.narration_context

    assert_match(/The player is carrying: Brass Key, Theodolite\./, context)
    assert_no_match(/carrying:.*Ledger/, context, "what lies on the floor is not in the player's hands")
  end

  # THE FOURTH CLOSED SET, and the last one the prose was not told about. The
  # classifier resolves a `take` against exactly this list every turn; the
  # narrator used to know what the player was holding and not what they could
  # pick up, so prose answering a take that resolved to a real row had no idea
  # the thing was in the room. It is also what makes the item registry visible:
  # a generated room's furniture reaches the narrator through the records.
  test "the narration context lists what is lying here" do
    create(:item, :lying, location: @here, name: "Ledger")
    create(:item, :lying, location: @here, name: "Oil Lamp")
    create(:item, character: @protagonist, name: "Brass Key")
    create(:item, :lying, location: connect("The Sunken Stair"), name: "Crowbar")

    context = moment.narration_context

    assert_match(/Lying here, and takeable: Ledger, Oil Lamp\./, context)
    assert_no_match(/Lying here.*Brass Key/, context, "what the player is holding is not on the floor")
    assert_no_match(/Lying here.*Crowbar/, context, "what is lying in the next room is not lying here")
  end

  # STATED EVEN WHEN EMPTY. Silence about the inventory is an invitation to
  # decide; "nothing" is a fact the narrator can use.
  test "empty sets are stated rather than left out" do
    context = moment.narration_context

    assert_match(/Ways out of here: none\./, context)
    assert_match(/Nobody else is here\./, context)
    assert_match(/Lying here, and takeable: nothing\./, context)
    assert_match(/The player is carrying: nothing\./, context)
  end

  test "the narration context carries the room, the last turn and the recap" do
    stands_here("Maren Vosk")
    first = create(:scene, story: @story, location: @here, summary: "The player came in out of the rain.",
                           description: "Long prose about the rain.")
    second = create(:scene, story: @story, location: @here, previous_scene: first,
                            description: "Maren looks up from the crate.")
    @playthrough.update!(current_scene: second)

    context = moment.narration_context

    assert_match(/The player is in Ashgate Market: Stalls under wet canvas\./, context)
    assert_match(/What just happened: Maren looks up from the crate\./, context)
    assert_match(/Earlier, in order:\nThe player came in out of the rain\./, context)
    assert_no_match(/Long prose about the rain/, context)
  end

  test "a playthrough standing nowhere has no room and no ways out to speak of" do
    nowhere = create(:playthrough, story: @story, character: @protagonist)

    context = Playthrough::Moment.new(nowhere).narration_context

    assert_no_match(/Ways out of here/, context)
    assert_match(/Nobody else is here\./, context)
  end

  # --- the character's moment ----------------------------------------------

  # THE ROOM'S NAME AND NOT ITS DESCRIPTION: the durable chat replays this
  # block on the next two turns, so it is kept to what a person in the room
  # would actually be aware of.
  test "the character context names the room, the hour and what the player just did" do
    maren = stands_here("Maren Vosk")
    @playthrough.current_scene.update!(story_timestamp: Time.utc(2026, 8, 31, 23, 0))

    context = moment.character_context(maren)

    assert_match(/Where you are: Ashgate Market\./, context)
    assert_match(/The time is about 11 pm\./, context)
    assert_match(/What Iri Calder did a moment ago: "shake the rain off my coat"/, context)
    assert_no_match(/Stalls under wet canvas/, context, "the description is the narrator's, not the character's")
    assert_no_match(/the player/i, context, "the engine's stand-in for the player is not in this register")
  end

  # THE LAST TURN IS QUOTED FROM THE RECORD, NEVER FROM THE PROSE THAT ANSWERED
  # IT. Both of the shapes `Scene.recap_line` would have replayed here are
  # measured leaks: a narrated turn has no summary, so the fallback is the
  # narrator's second person, and every other "you" in a character prompt means
  # the character (6 wrong turns in 10, Fisher p = 0.011); a talk turn's summary
  # tells the character that "the player" spoke with itself.
  test "the character context carries no second-person prose after a narrated turn" do
    maren = create(:character, story: @story, fullname: "Maren Vosk")
    narrated = create(:scene, story: @story, location: @here, characters: [ maren ],
                              typed: "check the daybook",
                              summary: nil,
                              description: "You run your thumb down the ruled gap between four and five.")
    @playthrough.update!(current_scene: narrated)

    context = moment.character_context(maren)

    assert_match(/What Iri Calder did a moment ago: "check the daybook"/, context)
    assert_no_match(/\byou\b/i, context.lines.grep(/a moment ago/).join)
    assert_no_match(/run your thumb/, context, "the narrator's second person is addressed to the player, not to this character")
  end

  test "the character context does not tell a character that the player spoke with it" do
    maren = create(:character, story: @story, fullname: "Maren Vosk")
    talked = create(:scene, story: @story, location: @here, characters: [ @protagonist, maren ],
                            typed: "ask her about the ledger",
                            summary: "The player spoke with Maren Vosk. She nods.")
    @playthrough.update!(current_scene: talked)

    context = moment.character_context(maren)

    assert_match(/What Iri Calder did a moment ago: "ask her about the ledger"/, context)
    assert_no_match(/the player/i, context)
    assert_no_match(/spoke with Maren Vosk/, context)
  end

  # The opening arrival is a turn nobody took, so there is nothing to quote and
  # the character is told nothing rather than told it wrong.
  test "a character is told nothing about a turn nobody typed" do
    maren = create(:character, story: @story, fullname: "Maren Vosk")
    opening = create(:scene, story: @story, location: @here, characters: [ maren ], typed: nil,
                             description: "You come in out of the rain.")
    @playthrough.update!(current_scene: opening)

    assert_no_match(/a moment ago/, moment.character_context(maren))
  end

  test "the character context names the others in the room, and neither of the two talking" do
    maren = stands_here("Maren Vosk")
    bystander = create(:character, story: @story, fullname: "Tobin Ashe", nickname: "Tobin", location: @here)

    context = moment.character_context(maren)

    assert_match(/Also here, besides the two of you: Tobin Ashe \(Tobin\)\./, context)
    assert_no_match(/besides the two of you:.*Maren/, context)
    assert_no_match(/besides the two of you:.*Iri/, context)
  end

  test "a character alone with the player is told about nobody else" do
    maren = stands_here("Maren Vosk")

    assert_no_match(/Also here/, moment.character_context(maren))
  end

  # --- what the character has already concluded ----------------------------

  # THE MEMORY THE DESIGN SAID EXISTED. The default for `replayed` is
  # `Chat::HISTORY_EXCHANGES`, an env-tunable constant, so the tests state it.
  # `Interaction` keeps every exchange and
  # `Chat#prune_history!` keeps the last two verbatim; nothing had ever read the
  # rest back into a prompt.
  test "the character is reminded what it concluded on exchanges the chat no longer replays" do
    maren = stands_here("Maren Vosk")
    exchanges = converse(maren, "I will hear this stranger out.",
                                "She is lying about the ledger.",
                                "I will not mention the cellar again.",
                                "Whatever she wants, it is not the rent.")

    context = moment.character_context(maren, replayed: 2)

    assert_match(/What you have already concluded about Iri Calder/, context)
    assert_match(/- I will hear this stranger out\./, context)
    assert_match(/- She is lying about the ledger\./, context)
    assert_no_match(/cellar again/, context, "the last two exchanges are replayed verbatim already")
    assert_no_match(/not the rent/, context)

    assert_equal 4, exchanges.count
  end

  test "a conversation that has not outgrown the replay has nothing to be reminded of" do
    maren = stands_here("Maren Vosk")
    converse(maren, "I will hear this stranger out.")

    assert_no_match(/already concluded/, moment.character_context(maren, replayed: 2))
  end

  test "conclusions from another playthrough of the same world are not this one's" do
    maren = stands_here("Maren Vosk")
    other = create(:playthrough, story: @story, current_location: @here)
    other_scene = create(:scene, story: @story, location: @here)
    other.update!(current_scene: other_scene)
    3.times { |n| record_exchange(maren, other_scene, "Somebody else's conclusion #{n}.") }

    assert_empty moment.conclusions(maren, replayed: 0)
  end

  # THE CHARACTER'S OWN RECORDED ACTION, not `Interaction#summary`. The summary
  # is composed for the engine as `the player said "..."` (Interaction#compose_summary)
  # and these sentences are read back into the character's own prompt, where
  # "the player" is a stand-in nobody in the room would use.
  test "conclusions fall back to what the character did when nothing was resolved" do
    maren = stands_here("Maren Vosk")
    record_exchange(maren, @playthrough.current_scene, nil, summary: "the player said \"hello\" -- She nods.")

    assert_equal [ "She nods." ], moment.conclusions(maren, replayed: 0)
    assert_no_match(/the player/i, moment.character_context(maren, replayed: 0))
  end

  test "conclusions stay under their budget, newest kept first" do
    maren = stands_here("Maren Vosk")
    converse(maren, "A" * 300, "B" * 300, "C" * 50)

    assert_equal [ "B" * 300, "C" * 50 ], moment.conclusions(maren, replayed: 0)
  end

  private

  # One talk turn per resolution, each on its own scene in this playthrough's chain.
  def converse(character, *resolutions)
    resolutions.map do |resolution|
      scene = create(:scene, story: @story, location: @here, previous_scene: @playthrough.current_scene,
                             characters: [ @protagonist, character ])
      @playthrough.update!(current_scene: scene)
      record_exchange(character, scene, resolution)
    end
  end

  def record_exchange(character, scene, resolution, summary: nil)
    Interaction.create!(
      character: character, scene: scene, location: @here, user_input: "hello",
      pre_thought: "Who is this?", pre_feeling: "wary", action: "She nods.",
      post_feeling: "steadier", post_thought: "Fine.", inner_resolution: resolution, summary: summary
    )
  end
end
