require "test_helper"

class Playthrough::MemoryTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @room = create(:location, story: @story)
    @player = create(:character, :protagonist, story: @story, fullname: "Cal", nickname: "Cal")
    @npc = create(:character, story: @story, location: @room, fullname: "Maren", nickname: "Maren")
    @opening = create(:scene, story: @story, location: @room, characters: [ @player, @npc ])
    @game = create(:playthrough, story: @story, character: @player, current_location: @room, current_scene: @opening)
  end

  test "a relevant old promise survives a long distinct conversation" do
    promise = exchange("I promised to lend Cal the brass key.", said: "Could I borrow the key later?")
    30.times { |n| exchange("I will inspect stall #{n} after the market closes.") }

    rows = recall(query: "May I borrow your brass key?", replayed: 2)

    assert_equal promise.id, rows.first
    assert_operator rows.size, :<=, EngineMoment::TABLES.fetch("conclusions")
    assert_includes EngineMoment.new(@game).character_context(@npc, query: "borrow brass key"), promise.inner_resolution
  end

  test "repeated resolutions use one slot and the latest source" do
    exchange("Cal harmed my family. I will not trust him with my brass key.")
    repeated = 15.times.map { exchange("I will sweep the market after lunch.") }

    rows = recall(query: "brass key", replayed: 0)

    assert_equal 2, rows.size
    assert_includes rows, repeated.last.id
    assert_empty rows & repeated[0...-1].map(&:id)
  end

  test "different admissions with the same resolution remain distinct experiences" do
    first = exchange("I will remember what Cal told me.", said: "I burned your family's boat.")
    second = exchange("I will remember what Cal told me.", said: "I returned your missing medicine.")

    assert_equal [ first.id, second.id ].sort, recall(query: "boat medicine", replayed: 0).sort
  end

  test "distinct spoken arrangements survive generic identical private resolutions" do
    first = exchange("I will remember our meeting arrangements.", said: "Where should we meet?")
    first.update!(action: "Meet me under the old bridge at dusk.")
    second = exchange("I will remember our meeting arrangements.", said: "Where should we meet?")
    second.update!(action: "Meet me beside the stone well at dawn.")
    2.times { exchange("I will sweep today.") }

    assert_equal [ first.id, second.id ].sort, recall(query: "Where should we meet?", replayed: 2).sort
    prompt = EngineMoment.new(@game).character_prompt(@npc, "Where should we meet?")
    assert_includes prompt, 'You remember responding: "Meet me beside the stone well at dawn."'
    assert_operator prompt.index("old bridge"), :<, prompt.index("stone well")
  end

  test "a character cannot recall another character's private resolution or another game's exchange" do
    other_npc = create(:character, story: @story, location: @room)
    secret = exchange("I hid the brass key under my bed.", character: other_npc)
    other_game = create(:playthrough, story: @story, character: @player, current_location: @room, current_scene: @opening)
    own = exchange("I will never lend Cal my brass key.")

    assert_equal [ own.id ], recall(query: "brass key", replayed: 0)
    assert_empty EngineMoment.new(other_game).recall(@npc, query: "brass key", replayed: 0)
    assert_not_includes recall(query: "brass key", replayed: 0), secret.id
  end

  test "the recollection attributes an admission instead of asserting the event as verified" do
    row = exchange("Cal burned my boat. I will not trust him.", said: "I burned your boat.")
    text = EngineMoment.new(@game).recollection(@npc, row)

    assert_includes text, 'You heard Cal say: "I burned your boat."'
    assert_includes text, 'You then concluded: "Cal burned my boat. I will not trust him."'
    assert_not_includes text, "The recorded result was"
  end

  test "only an applied receipt is included as a recorded result" do
    row = exchange("I will keep my key.")
    row.update!(action_status: "rejected", action_fact: "A transfer was rejected.")
    assert_not_includes EngineMoment.new(@game).recollection(@npc, row), "The recorded result was"
    row.update!(action_status: "applied", action_fact: "Maren gave Cal the brass key.")
    assert_includes EngineMoment.new(@game).recollection(@npc, row), "The recorded result was: Maren gave Cal the brass key."
  end

  test "the emitted recollections stay under their budget and in chronological order" do
    12.times { |n| exchange("Promise #{n}: " + "I will help with the brass key. " * 8) }
    moment = EngineMoment.new(@game)
    entries = moment.recollections(@npc, replayed: 0, query: "brass key")

    assert_operator entries.sum(&:length), :<=, EngineMoment::TABLES.fetch("memories_budget")
    assert_not_empty entries
    numbers = entries.map { |text| text[/Promise (\d+)/, 1].to_i }
    assert_equal numbers.sort, numbers
  end

  test "a new reader retrieves the same sources from persisted rows" do
    wanted = exchange("I will lend Cal my brass key.")
    9.times { exchange("I will sweep today.") }

    cold = EngineMoment.new(Playthrough.find(@game.id))
    assert_equal wanted.id, cold.recall(Character.find(@npc.id), query: "brass key").first
  end

  private

  # What Maren recalls in this game, as the engine ranks it: interaction ids.
  def recall(**arguments) = EngineMoment.new(@game).recall(@npc, **arguments)

  def exchange(resolution, said: "Hello.", character: @npc)
    scene = create(:scene, story: @story, location: @room, previous_scene: @game.current_scene,
                           characters: [ @player, character ])
    @game.update!(current_scene: scene)
    create(:interaction, scene: scene, location: @room, character: character,
                         user_input: said, inner_resolution: resolution)
  end
end
