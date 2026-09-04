require "test_helper"

class PlaythroughTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @playthrough = build(:playthrough, story: @story)
  end

  test "should be valid with valid attributes" do
    assert @playthrough.valid?
  end

  test "should require a story" do
    @playthrough.story = nil
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:story], "must exist"
  end

  test "should generate a token on initialize" do
    assert @playthrough.token.present?
    assert_operator @playthrough.token.length, :>=, 24
  end

  test "should require a token" do
    @playthrough.token = nil
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:token], "can't be blank"
  end

  test "should require a unique token" do
    existing = create(:playthrough)
    @playthrough.token = existing.token
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:token], "has already been taken"
  end

  test "should generate distinct tokens" do
    tokens = 5.times.map { create(:playthrough).token }
    assert_equal tokens.uniq.length, tokens.length
  end

  test "should allow a character, location and scene from its own story" do
    location = create(:location, story: @story)
    @playthrough.character = create(:character, story: @story)
    @playthrough.current_location = location
    @playthrough.current_scene = create(:scene, story: @story, location: location)

    assert @playthrough.valid?
  end

  test "should be valid with no character, location or scene" do
    assert_nil @playthrough.character
    assert_nil @playthrough.current_location
    assert_nil @playthrough.current_scene
    assert @playthrough.valid?
  end

  test "should reject a character from another story" do
    @playthrough.character = create(:character, story: create(:story))
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:character], "must belong to the playthrough's story"
  end

  test "should reject a current location from another story" do
    @playthrough.current_location = create(:location, story: create(:story))
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:current_location], "must belong to the playthrough's story"
  end

  test "should reject a current scene from another story" do
    other_story = create(:story)
    @playthrough.current_scene = create(:scene, story: other_story, location: create(:location, story: other_story))
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:current_scene], "must belong to the playthrough's story"
  end

  test "should belong to a story" do
    playthrough = create(:playthrough, story: @story)
    assert_equal @story, playthrough.story
    assert_includes @story.playthroughs, playthrough
  end

  test "should reference the protagonist and their position" do
    playthrough = create(:playthrough, :started, story: @story)

    assert playthrough.character.is_protagonist?
    assert_equal @story, playthrough.character.story
    assert_equal @story, playthrough.current_location.story
    assert_includes playthrough.character.playthroughs, playthrough
    assert_includes playthrough.current_location.playthroughs, playthrough
  end

  test "should track the current scene" do
    playthrough = create(:playthrough, :in_scene, story: @story)

    assert_equal playthrough.current_location, playthrough.current_scene.location
    assert_includes playthrough.current_scene.playthroughs, playthrough
  end

  # --- where this playthrough stands on the story's clock ------------------

  test "story_now is the story moment of the scene the player is in" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    scene = create(:scene, story: story, location: create(:location, story: story),
                           story_timestamp: story.start_time + 3.hours)
    playthrough = create(:playthrough, story: story, current_scene: scene)

    assert_equal story.start_time + 3.hours, playthrough.story_now
  end

  # Per-playthrough rather than story-wide: one world can be played twice, and a
  # second player's progress must not drag the first player's next turn forward.
  test "story_now follows this playthrough rather than the story's high-water mark" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    location = create(:location, story: story)
    mine = create(:scene, story: story, location: location, story_timestamp: story.start_time + 1.hour)
    create(:scene, story: story, location: location, story_timestamp: story.start_time + 10.days)
    playthrough = create(:playthrough, story: story, current_scene: mine)

    assert_equal story.start_time + 1.hour, playthrough.story_now
    assert_equal story.start_time + 10.days, story.clock
  end

  test "story_now falls back to the story's clock before the first turn" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    playthrough = create(:playthrough, story: story)

    assert_equal story.start_time, playthrough.story_now
  end

  test "story_time_after costs a turn what its kind costs" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    playthrough = create(:playthrough, story: story)

    assert_equal story.start_time + 10.minutes, playthrough.story_time_after("conversation")
    assert_equal story.start_time + 5.minutes, playthrough.story_time_after("action")
  end

  test "story_time_after refuses a kind of turn nobody has priced" do
    playthrough = create(:playthrough, story: create(:story))

    assert_raises(KeyError) { playthrough.story_time_after("teleporting") }
  end

  test "should be destroyed with its story" do
    playthrough = create(:playthrough, story: @story)
    @story.destroy

    assert_not Playthrough.exists?(playthrough.id)
  end

  test "should survive its character being destroyed" do
    playthrough = create(:playthrough, :started, story: @story)
    playthrough.character.destroy

    assert_nil playthrough.reload.character_id
  end

  test "should survive its current location being destroyed" do
    playthrough = create(:playthrough, :in_scene, story: @story)
    playthrough.current_location.destroy

    playthrough.reload
    assert_nil playthrough.current_location_id
    assert_nil playthrough.current_scene_id
  end

  # THE TURN LOG. It walks backwards from `current_scene`, so two playthroughs
  # branching off one opening arrival each read their own turns. It lives on the
  # model rather than in the controller because `NarrationJob` renders the same
  # log when it broadcasts a finished turn, and a job has no controller to
  # borrow a private method from.
  test "turn_log walks back from the current scene, oldest first" do
    playthrough = create(:playthrough, :in_scene, story: @story)
    opening = playthrough.current_scene
    second = create(:scene, story: @story, location: playthrough.current_location,
                            description: "Rain starts falling.", previous_scene: opening)
    playthrough.update!(current_scene: second)

    assert_equal [ opening, second ], playthrough.turn_log
  end

  test "turn_log is empty for a playthrough that has not started" do
    assert_empty create(:playthrough, story: @story).turn_log
  end

  test "turn_log reads only this playthrough's turns" do
    opening = create(:scene, :opening, story: @story, location: create(:location, story: @story))
    mine = create(:playthrough, story: @story, current_location: opening.location,
                                current_scene: create(:scene, story: @story, location: opening.location,
                                                              description: "I turn left.", previous_scene: opening))
    create(:playthrough, story: @story, current_location: opening.location,
                         current_scene: create(:scene, story: @story, location: opening.location,
                                                       description: "They turn right.", previous_scene: opening))

    assert_equal [ opening.description, "I turn left." ], mine.turn_log.map(&:description)
  end

  # The exits are the move targets `Playthrough::Classifier` will accept, which
  # is why the play page prints them.
  test "exits are the ways out of where the player is standing" do
    playthrough = create(:playthrough, :started, story: @story)
    there = create(:location, story: @story, name: "The Sunken Stair")
    create(:location_connection, location: playthrough.current_location, connected_location: there)

    assert_equal [ there ], playthrough.exits.to_a
  end

  test "exits are empty when the player is nowhere yet" do
    assert_empty create(:playthrough, story: @story).exits
  end

  # --- the recap: summarising old scenes so a long game stays in the window ---

  # `scenes.summary` has been written on every arrival all along, for exactly
  # this. The recap spends it -- no model call, no second history.
  test "recap is built from the summaries the arrivals already wrote" do
    playthrough = create(:playthrough, :started)
    first = scene_in(playthrough, summary: "You arrived at the ward office.")
    second = scene_in(playthrough, summary: "You met Rowe in the doorway.", previous_scene: first)
    third = scene_in(playthrough, summary: "You went down to the archive.", previous_scene: second)
    playthrough.update!(current_scene: third)

    assert_equal "You arrived at the ward office.\nYou met Rowe in the doorway.", playthrough.recap
  end

  # It never repeats the scene the caller is already putting in the prompt in
  # full -- that is what `before` is for, and by default it is the current one.
  test "recap excludes the turn the prompt already carries" do
    playthrough = create(:playthrough, :started)
    first = scene_in(playthrough, summary: "Earlier.")
    second = scene_in(playthrough, summary: "Just now.", previous_scene: first)
    playthrough.update!(current_scene: second)

    assert_equal "Earlier.", playthrough.recap
    assert_nil playthrough.recap(before: first)
  end

  # Only an arrival is summarised by the model. A narrated turn is not, and
  # truncating what it wrote is honest where a second call per turn is not.
  test "a turn with no summary contributes its own first sentence" do
    playthrough = create(:playthrough, :started)
    first = scene_in(playthrough, summary: nil,
                     description: "You crouch by the grate. Water moves under it, somewhere.")
    second = scene_in(playthrough, summary: "Later.", previous_scene: first)
    playthrough.update!(current_scene: second)

    assert_equal "You crouch by the grate.", playthrough.recap
  end

  # THE BUDGET IS THE POINT. A prompt that quietly forgets is worse than one
  # that says it has forgotten, so the drop is stated rather than silent.
  test "recap stays inside its budget and says what it left out" do
    playthrough = create(:playthrough, :started)
    previous = nil
    5.times { |n| previous = scene_in(playthrough, summary: "#{n}: #{"x" * 40}", previous_scene: previous) }
    playthrough.update!(current_scene: scene_in(playthrough, summary: "now", previous_scene: previous))

    recap = playthrough.recap(budget: 100)

    assert_operator recap.length, :<=, 100 + 40, "the budget governs the summaries, not the notice"
    assert_match(/earlier turns? left out/, recap)
    assert_includes recap, "4: "
    assert_not_includes recap, "0: "
  end

  test "a playthrough with nothing behind it has no recap" do
    playthrough = create(:playthrough, :started)
    playthrough.update!(current_scene: scene_in(playthrough, summary: "the only turn"))

    assert_nil playthrough.recap
  end

  # --- pruning the audit trail ----------------------------------------------

  # This is a SQLite file on a laptop and the game never reads any of this back.
  test "prune_conversations! drops one-shot conversations older than the last few turns" do
    playthrough = create(:playthrough, :started)
    old_scene = scene_in(playthrough)
    new_scene = scene_in(playthrough, previous_scene: old_scene)
    playthrough.update!(current_scene: new_scene)

    old_chat = chat_for(playthrough, old_scene, purpose: "classifier")
    new_chat = chat_for(playthrough, new_scene, purpose: "classifier")

    assert_equal 1, playthrough.prune_conversations!(keep: 1)
    assert_not Chat.exists?(old_chat.id)
    assert Chat.exists?(new_chat.id)
    assert_equal 0, Message.where(chat_id: old_chat.id).count, "its messages go with it"
  end

  # Deleting one of these would give a character amnesia. They are bounded a
  # different way -- message by message, when they are picked up.
  test "prune_conversations! never touches a durable conversation" do
    playthrough = create(:playthrough, :started)
    old_scene = scene_in(playthrough)
    playthrough.update!(current_scene: scene_in(playthrough, previous_scene: old_scene))

    durable = chat_for(playthrough, old_scene, purpose: Chat::CHARACTER,
                                               character: create(:character, story: playthrough.story))

    assert_equal 0, playthrough.prune_conversations!(keep: 1)
    assert Chat.exists?(durable.id)
  end

  # A conversation whose messages carry no scene belongs to a turn still being
  # played, or one that failed before it produced a scene. Neither is old.
  test "prune_conversations! leaves an unattributed conversation alone" do
    playthrough = create(:playthrough, :started)
    playthrough.update!(current_scene: scene_in(playthrough))
    in_flight = create(:chat, playthrough: playthrough, purpose: "classifier")
    create(:message, chat: in_flight)

    assert_equal 0, playthrough.prune_conversations!(keep: 1)
    assert Chat.exists?(in_flight.id)
  end

  test "destroying a playthrough takes its conversations with it" do
    playthrough = create(:playthrough, :started)
    create(:chat, playthrough: playthrough, purpose: "classifier")

    assert_difference -> { Chat.count }, -1 do
      playthrough.destroy
    end
  end

  private

  def scene_in(playthrough, previous_scene: nil, summary: "a summary", description: "Prose.")
    create(:scene, story: playthrough.story, location: playthrough.current_location,
                   previous_scene: previous_scene, summary: summary, description: description)
  end

  def chat_for(playthrough, scene, purpose:, character: nil)
    chat = create(:chat, playthrough: playthrough, purpose: purpose, character: character)
    create(:message, chat: chat, scene: scene)
    create(:message, :assistant, chat: chat, scene: scene)
    chat
  end
  # --- what the party is carrying ---------------------------------------------
  #
  # THE DEFECT THIS COLUMN CLOSES: the inventory used to be
  # `items.character_id` pointing at `story.protagonist` -- one Character row
  # per story -- so every playthrough of one world shared one set of things and
  # a new game opened holding the last game's loot.

  test "carried is this party's own things and nobody else's" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    mine = create(:playthrough, story: story, character: protagonist)
    theirs = create(:playthrough, story: story, character: protagonist)

    key = create(:item, :carried, playthrough: mine, name: "Brass Key")
    create(:item, :carried, playthrough: theirs, name: "Iron Ledger")

    assert_equal [ key ], mine.carried.to_a
  end

  test "what one of the world's own people holds is not what any party carries" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    landlord = create(:character, story: story, fullname: "Grenn Ollivar")
    played = create(:playthrough, story: story, character: protagonist)
    create(:item, character: landlord, name: "Iron Ledger")

    assert_empty played.carried
  end

  # A COPY, not the row itself: `Story#starting_inventory` is world data -- the
  # seed file writes it and the exporter reads it back -- and an `Item` is in
  # exactly one place, so a second player starting must not find the daybook
  # already in somebody else's hands.
  test "a new playthrough takes up its own copy of the story's starting inventory" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    daybook = create(:item, character: protagonist, name: "Ward Office 12 daybook")

    played = create(:playthrough, story: story, character: protagonist)

    assert_equal [ daybook.name ], played.carried.pluck(:name)
    assert_not_equal daybook.id, played.carried.sole.id
    assert_equal daybook.properties, played.carried.sole.properties, "a copy of a thing is that thing"
    assert_equal protagonist, daybook.reload.character, "the world's own row is left where it is"
  end

  # WHAT IS WRITTEN ON IT COMES ALONG, and the copy is asserted by column rather
  # than by field list on purpose: naming the fields is what silently left
  # `readable` and `inscription` behind, so each player's copy of a seeded note
  # opened blank while the world's own row held the words. `NOT_COPIED` is the
  # whole of what must not travel.
  test "the kit's copy of a readable thing keeps what is written on it" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    note = create(:item, :readable, character: protagonist, name: "a folded note")

    copy = create(:playthrough, story: story, character: protagonist).carried.sole

    assert copy.readable?
    assert copy.inscribed?
    assert_equal note.inscription, copy.inscription
  end

  # EVERY COLUMN BUT WHERE IT IS. A column added to `items` later must come
  # along without anybody remembering to add it here.
  test "the kit copies every column except the three that say where a thing is" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    original = create(:item, :readable, character: protagonist, name: "a folded note")

    copy = create(:playthrough, story: story, character: protagonist).carried.sole
    ignored = Playthrough::NOT_COPIED

    assert_equal original.attributes.except(*ignored), copy.attributes.except(*ignored)
    assert_equal Item::PLACES.map(&:to_s).sort, (ignored - %w[id created_at updated_at]).sort
    assert_nil copy.character_id
    assert_nil copy.location_id
  end

  test "two playthroughs of one world start with the same kit and carry two different sets" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    room = create(:location, story: story)
    create(:item, character: protagonist, name: "Ward Office 12 daybook")

    first = create(:playthrough, story: story, character: protagonist, current_location: room)
    second = create(:playthrough, story: story, character: protagonist, current_location: room)
    create(:item, :lying, location: room, name: "ward stamp").update!(playthrough: first, location: nil)

    assert_equal [ "Ward Office 12 daybook", "ward stamp" ], first.carried.pluck(:name).sort
    assert_equal [ "Ward Office 12 daybook" ], second.carried.pluck(:name)
  end

  test "a story with no starting inventory starts a playthrough empty-handed" do
    story = create(:story)
    create(:character, :protagonist, story: story)

    assert_empty create(:playthrough, story: story).carried
  end

  # A playthrough handed items in the same breath as its creation -- which a
  # test fixture may do -- must not also be given the kit.
  test "a playthrough that already carries something is not issued the kit" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    create(:item, character: protagonist, name: "Ward Office 12 daybook")

    played = Playthrough.new(story: story, character: protagonist)
    played.items.build(name: "Brass Key", description: "cold")
    played.save!

    assert_equal [ "Brass Key" ], played.carried.pluck(:name)
  end
end
