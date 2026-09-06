require "test_helper"

class Playthrough::MachineryTest < ActiveSupport::TestCase
  # THE HARD RULE, inherited from `Playthrough::Debug` and asserted here rather
  # than assumed: this is an observer. Opening an inspector must not generate,
  # mutate a record, or advance a playthrough -- and in particular it must not
  # snapshot the room's items, which is the one write a reader that touched
  # `Item::Snapshot` instead of `Playthrough#items_lying_in` would make.
  #
  # Asserted against every table and against `maximum(:updated_at)` as well as
  # counts, exactly as `Playthrough::DebugTest` does, so an update in place is
  # caught along with an insert.
  test "reading a turn's machinery writes nothing" do
    playthrough, scene = played_turn
    before = database_snapshot

    BaseAgent.stub(:new, -> { flunk "the inspector asked a model something" }) do
      read_everything(Playthrough::Machinery.new(playthrough, scene))
    end

    assert_equal before, database_snapshot
  end

  # ------------------------------------------------------------------------
  # THE FIVE ROWS, and which of them the records can answer historically.
  # ------------------------------------------------------------------------

  # (1) and (2) are columns written when the turn was played, so they are as of
  # the turn -- and the test proves it by moving the world afterwards and
  # checking the panel does not follow.
  test "the story time and the cast are the turn's own, not the world as it stands" do
    playthrough, scene = played_turn
    grenn = scene.characters.find { |who| who != playthrough.character }

    # The world moves on: Grenn walks out of the room after the turn was played.
    grenn.update!(location: create(:location, story: playthrough.story))

    machinery = Playthrough::Machinery.new(playthrough, scene)

    assert_equal scene.story_timestamp, machinery.story_time
    assert_includes machinery.cast, grenn, "the cast is the snapshot, not Character.present_in"
  end

  # (3), (4) and (5) are `Item` rows, which say where a thing is NOW. There is
  # no history to read, and the panel says so rather than implying one.
  test "the three item rows read this playthrough's own layer" do
    playthrough, scene = played_turn
    here = scene.location
    lantern = lying_here(playthrough, here, name: "A cracked lantern")
    create(:item, :carried, playthrough: playthrough, name: "A brass ledger")

    machinery = Playthrough::Machinery.new(playthrough, scene)

    assert_equal [ lantern.id ], machinery.lying_here.map(&:id)
    assert_equal [ "A brass ledger" ], machinery.carried.map(&:name)
  end

  # THE WORLD'S OWN ROWS ARE NOT THIS GAME'S. A template lying in the room is
  # what a playthrough copies FROM, and a panel that showed it would report an
  # item the player cannot take.
  test "a template lying in the room is not reported as lying here" do
    playthrough, scene = played_turn
    create(:item, :lying, location: scene.location, name: "A world template")

    assert_empty Playthrough::Machinery.new(playthrough, scene).lying_here.map(&:name)
  end

  # (5) IS PER PERSON AND THE PROTAGONIST IS NOT ONE OF THEM: the party's own
  # hands are row (4), and a party's copies are in neither a room nor anybody's
  # hands, so listing the protagonist here would print an empty line that reads
  # as a bug.
  test "what each person present carries excludes the protagonist" do
    playthrough, scene = played_turn
    grenn = scene.characters.find { |who| who != playthrough.character }
    create(:item, :carried, playthrough: playthrough, name: "A brass ledger")
    create(:item, playthrough: playthrough, character: grenn, name: "A tide slate")

    held = Playthrough::Machinery.new(playthrough, scene).held

    assert_equal [ grenn ], held.map(&:character)
    assert_equal [ "A tide slate" ], held.sole.items.map(&:name)
  end

  test "somebody present holding nothing is still a row" do
    playthrough, scene = played_turn

    assert_empty Playthrough::Machinery.new(playthrough, scene).held.sole.items
  end

  # ------------------------------------------------------------------------
  # THE PROMPT HALF, read off the same records the debug page reads.
  # ------------------------------------------------------------------------

  # THE PROSE CALL FIRST AND THE CLASSIFIER SECOND, which is the opposite of the
  # order the loop made them in: the passage is being compared against the
  # prompt that produced it, and the classification is context for that.
  test "the prose call and the classifier call are separated and ordered for reading" do
    playthrough, scene = played_turn
    classifier = exchange_on(scene, purpose: "classifier")
    narration = exchange_on(scene, purpose: "narration")

    machinery = Playthrough::Machinery.new(playthrough, scene)

    assert_equal [ narration.id ], machinery.prose_conversations.map { |one| one.chat.id }
    assert_equal [ classifier.id ], machinery.classifier_conversations.map { |one| one.chat.id }
    assert machinery.receipts?
  end

  # A turn the grammar read made no classifier call at all -- the whole point of
  # the slash menu -- and that is an absence to report rather than a gap.
  test "a turn with no classifier call reports none" do
    playthrough, scene = played_turn
    exchange_on(scene, purpose: "narration")

    assert_empty Playthrough::Machinery.new(playthrough, scene).classifier_conversations
  end

  test "a turn with no receipts at all says so" do
    playthrough, scene = played_turn

    machinery = Playthrough::Machinery.new(playthrough, scene)

    assert_not machinery.receipts?
    assert_empty machinery.prose_conversations
  end

  # THE DIGEST THE WHOLE COMPARISON HANGS ON. `Playthrough::PromptVersion` is
  # what `Playthrough::Feedback` freezes and what `rake eval:prompt` records, so
  # a panel showing a different one would make two turns look comparable when
  # they are not.
  test "an exchange carries the digest of the instructions it was under" do
    playthrough, scene = played_turn
    exchange_on(scene, purpose: "narration", instructions: "You are the narrator.")

    exchange = Playthrough::Machinery.new(playthrough, scene).prose_conversations.sole

    assert_equal Playthrough::PromptVersion.of("You are the narrator."), exchange.prompt_version
  end

  # `interaction-narration` sends no system message at all -- its prose rules are
  # interpolated into the per-turn user prompt -- so nil is the honest answer.
  test "an exchange with no system message has no digest" do
    playthrough, scene = played_turn
    exchange_on(scene, purpose: "interaction-narration", instructions: nil)

    assert_nil Playthrough::Machinery.new(playthrough, scene).prose_conversations.sole.prompt_version
  end

  private

  # A playthrough standing on a turn it played, with one of the world's people
  # in the room and recorded on the turn.
  def played_turn
    playthrough = create(:playthrough, :started)
    story = playthrough.story
    here = playthrough.current_location

    opening = create(:scene, :opening, story: story, location: here, story_timestamp: story.start_time)
    grenn = create(:character, story: story, fullname: "Grenn Ollivar", location: here)
    scene = create(:scene, story: story, location: here, previous_scene: opening,
                           story_timestamp: story.start_time + 10.minutes,
                           typed: "ask Grenn about the charts")
    scene.characters = [ playthrough.character, grenn ]
    playthrough.update!(current_scene: scene)

    [ playthrough, scene ]
  end

  # One stored conversation, stamped onto this turn the way `BaseAgent` stamps
  # one: `messages.scene_id` is what makes a turn's receipts a turn's.
  def exchange_on(scene, purpose:, instructions: "You are the narrator.")
    chat = create(:chat, purpose: purpose)
    create(:message, :system, chat: chat, content: instructions) if instructions
    create(:message, chat: chat, scene: scene, content: "what do you do?")
    create(:message, :assistant, chat: chat, scene: scene)
    chat
  end

  # Every public method, so a future addition that writes is caught by the test
  # that is already here.
  def read_everything(machinery)
    Playthrough::Machinery.public_instance_methods(false).each do |name|
      machinery.public_send(name)
    end
  end

  # Row counts and the newest `updated_at` per table -- `Playthrough::DebugTest`'s
  # snapshot, and deliberately the same one.
  def database_snapshot
    ActiveRecord::Base.connection.tables.sort.to_h do |table|
      rows = ActiveRecord::Base.connection.select_all("SELECT COUNT(*) AS c FROM #{table}").first["c"]
      updated =
        if ActiveRecord::Base.connection.column_exists?(table, :updated_at)
          ActiveRecord::Base.connection.select_all("SELECT MAX(updated_at) AS m FROM #{table}").first["m"]
        end

      [ table, [ rows, updated ] ]
    end
  end
end
