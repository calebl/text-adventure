require "test_helper"

# The one-time recovery: whose hands a thing is in, out of the turn that picked
# it up. What it refuses to do is the half worth testing -- an item is in one
# place, so a backfill that chose between two players would be inventing which
# of them has it.
class Item::InventoryBackfillTest < ActiveSupport::TestCase
  def setup
    @story = create(:story, start_time: Time.utc(2026, 9, 1, 5, 20))
    @protagonist = create(:character, story: @story, fullname: "Odile Vance", is_protagonist: true)
    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
  end

  def playthrough(at: @office)
    create(:playthrough, story: @story, character: @protagonist, current_location: at)
  end

  # THE SHAPE OF AN OLD DATABASE: the party's inventory on the story's one
  # protagonist row, which is where every playthrough of a world read it from.
  def in_the_protagonists_hands(name)
    create(:item, character: @protagonist, name: name)
  end

  # A turn of `playthrough` that took or dropped `item`, appended to that
  # playthrough's chain -- which is what makes it attributable to one player.
  def turn(playthrough, action, item, at: 1.hour.ago)
    scene = create(:scene, story: @story, location: @office, story_timestamp: at,
                           previous_scene: playthrough.current_scene,
                           typed: "#{action} the #{item.name}",
                           resolved_action: action, acted_on: item)
    playthrough.update!(current_scene: scene)
    scene
  end

  # NOT named `run`: that is `Minitest::Runnable#run`, and overriding it makes
  # the runner call this before setup has assigned anything.
  def backfill(dry_run: false, only: nil)
    Item::InventoryBackfill.new(@story).run(dry_run: dry_run, only: only)
  end

  # --- attributed ------------------------------------------------------------

  test "an item one playthrough's turn log records taking goes into that party's hands" do
    played = playthrough
    stamp = in_the_protagonists_hands("ward stamp")
    turn(played, "take", stamp)

    answer = backfill.sole

    assert_predicate answer, :attributed?
    assert_equal played, answer.playthrough
    assert_equal played, stamp.reload.playthrough
    assert_nil stamp.character_id
    assert_nil stamp.location_id
  end

  # AN ITEM IS IN ONE PLACE, so when two players both record taking it the last
  # one to do so is the one holding it -- which is the reading the engine itself
  # had when it overwrote `items.character_id`.
  test "the latest take wins when two playthroughs both took it" do
    first = playthrough
    second = playthrough
    stamp = in_the_protagonists_hands("ward stamp")
    turn(first, "take", stamp, at: 3.hours.ago)
    turn(second, "take", stamp, at: 1.hour.ago)

    answer = backfill.sole

    assert_predicate answer, :attributed?
    assert_equal second, answer.playthrough
    assert_equal second, stamp.reload.playthrough
  end

  # A chain that goes on to put it down is not holding it, so it is not in the
  # running -- even though the take is on record.
  test "a playthrough that dropped it again is not the one holding it" do
    dropper = playthrough
    keeper = playthrough
    stamp = in_the_protagonists_hands("ward stamp")
    turn(dropper, "take", stamp, at: 4.hours.ago)
    turn(dropper, "drop", stamp, at: 3.hours.ago)
    turn(keeper, "take", stamp, at: 2.hours.ago)

    assert_equal keeper, backfill.sole.playthrough
  end

  # --- refuses to guess ------------------------------------------------------

  # STORY TIME IS THE ONLY ORDER BETWEEN TWO SEPARATE GAMES, and `scenes.id`
  # deliberately does not break the tie: the row id says which player sat down
  # at the keyboard second, which is a fact about the database rather than about
  # either fiction.
  test "two playthroughs taking it at the same moment is left alone and reported by name" do
    first = playthrough
    second = playthrough
    stamp = in_the_protagonists_hands("ward stamp")
    at = Time.utc(2026, 9, 1, 6, 0)
    turn(first, "take", stamp, at: at)
    turn(second, "take", stamp, at: at)

    answer = backfill.sole

    assert_predicate answer, :ambiguous?
    assert_equal [ first, second ], answer.playthroughs
    assert_equal @protagonist, stamp.reload.character, "nothing is written when nothing decides it"
    assert_nil stamp.playthrough_id
  end

  # A turn with no `story_timestamp` is a real shape an older database holds --
  # `Story::Doctor#scene_rows` reports them -- and it cannot be ranked against
  # one that has it, so there is no order at all.
  test "takes with no story time at all leave the item alone" do
    first = playthrough
    second = playthrough
    stamp = in_the_protagonists_hands("ward stamp")
    turn(first, "take", stamp, at: 3.hours.ago).update_columns(story_timestamp: nil)
    turn(second, "take", stamp, at: 1.hour.ago)

    answer = backfill.sole

    assert_predicate answer, :ambiguous?
    assert_equal @protagonist, stamp.reload.character
  end

  # One candidate needs no order, so a single chain with an untimed turn is
  # still decided.
  test "one playthrough with an untimed take is still the one holding it" do
    only = playthrough
    stamp = in_the_protagonists_hands("ward stamp")
    turn(only, "take", stamp).update_columns(story_timestamp: nil)

    assert_equal only, backfill.sole.playthrough
  end

  # --- the starting inventory ------------------------------------------------

  # NO TAKE ON RECORD IS THE EVIDENCE: nobody ever picked it up, so the world
  # put it there. Only `WorldSeed::Loader` ever does, and a generated
  # protagonist is given nothing by anything in the app.
  test "an item nobody's turn log ever took is the story's starting inventory" do
    played = playthrough
    daybook = in_the_protagonists_hands("Ward Office 12 daybook")

    answer = backfill.sole

    assert_predicate answer, :starting?
    assert_equal @protagonist, daybook.reload.character, "the world's own row stays where it is"
    assert_equal [ "Ward Office 12 daybook" ], played.carried.pluck(:name)
  end

  # Before the column every playthrough was reading this very row, so leaving
  # them empty-handed would take the daybook out of a game in progress.
  test "every existing playthrough is given its own copy of the starting inventory" do
    parties = Array.new(3) { playthrough }
    daybook = in_the_protagonists_hands("Ward Office 12 daybook")

    backfill

    parties.each { |party| assert_equal [ daybook.name ], party.carried.pluck(:name) }
    assert_equal 3, Item.carried.count
    assert_not_equal daybook.id, parties.first.carried.sole.id, "a copy, not the row itself"
  end

  test "a second run hands the starting inventory out only once" do
    played = playthrough
    in_the_protagonists_hands("Ward Office 12 daybook")

    backfill

    assert_no_difference -> { Item.count } do
      backfill
    end
    assert_equal 1, played.carried.count
  end

  # --- unrecoverable ---------------------------------------------------------

  # A CHECKED-IN WORLD IS THE ONE CASE WHERE "no take on record" IS NOT ENOUGH:
  # the file says what the story starts the player with, so an item held by the
  # protagonist that the file does not name was taken on a turn nobody labelled.
  # `Playthrough::Turn#drop_item`'s rule then applies -- a player who walks away
  # leaves it where they left it.
  test "an item the world file does not start the player with is put down where the last party stands" do
    story = seeded_story
    played = create(:playthrough, story: story, character: story.protagonist,
                                  current_location: story.locations.find_by(name: "The Supply Closet"))
    stray = create(:item, character: story.protagonist, name: "a thing the file never mentions")

    answer = Item::InventoryBackfill.new(story).run.find { |result| result.item.id == stray.id }

    assert_predicate answer, :unrecoverable?
    assert_equal played.current_location, answer.location
    assert_equal played.current_location, stray.reload.location
    assert_nil stray.character_id
    assert_nil stray.playthrough_id
  end

  test "an item the world file does start the player with is the starting inventory" do
    story = seeded_story
    create(:playthrough, story: story, character: story.protagonist)
    daybook = create(:item, character: story.protagonist, name: "Ward Office 12 daybook")

    answer = Item::InventoryBackfill.new(story).run.find { |result| result.item.id == daybook.id }

    assert_predicate answer, :starting?
    assert_equal story.protagonist, daybook.reload.character
  end

  # --- what it leaves alone --------------------------------------------------

  test "what one of the world's own people is holding is not the party's inventory" do
    playthrough
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    ledger = create(:item, character: landlord, name: "Iron Ledger")

    backfill

    assert_equal landlord, ledger.reload.character
    assert_nil ledger.playthrough_id
  end

  test "an item already carried by a party is not touched" do
    played = playthrough
    key = create(:item, :carried, playthrough: played, name: "Brass Key")

    assert_empty backfill
    assert_equal played, key.reload.playthrough
  end

  test "items lying in rooms are the world and are left where they are" do
    playthrough
    stamp = create(:item, :lying, location: @office, name: "ward stamp")

    assert_empty backfill
    assert_equal @office, stamp.reload.location
  end

  # --- the dry run -----------------------------------------------------------

  test "a dry run writes nothing at all and reports the same answers" do
    played = playthrough
    stamp = in_the_protagonists_hands("ward stamp")
    in_the_protagonists_hands("Ward Office 12 daybook")
    turn(played, "take", stamp)

    answers = nil
    assert_no_difference -> { Item.count } do
      answers = backfill(dry_run: true)
    end

    assert_equal [ :attributed, :starting ].to_set, answers.map(&:outcome).to_set
    assert_equal @protagonist, stamp.reload.character
    assert_empty played.carried
    assert_equal 1, answers.find(&:starting?).playthroughs.size,
                 "the dry run's figures are the figures the real run produces"
  end

  test "only: narrows the run to one item, which is what a repair asks for" do
    played = playthrough
    stamp = in_the_protagonists_hands("ward stamp")
    other = in_the_protagonists_hands("Perrin's private index")
    turn(played, "take", stamp)
    turn(played, "take", other)

    answers = backfill(only: stamp.id)

    assert_equal [ stamp.id ], answers.map { |answer| answer.item.id }
    assert_equal played, stamp.reload.playthrough
    assert_equal @protagonist, other.reload.character, "the other item is untouched"
  end

  test "a story with no protagonist has nothing to speak for" do
    assert_empty Item::InventoryBackfill.new(create(:story)).run
  end

  private

  # A story whose title matches a CHECKED-IN world file, which is the only kind
  # this reads the file for. Rooms are made by hand rather than loaded: the file
  # is consulted for the protagonist's item names and nothing else.
  def seeded_story
    story = create(:story, title: "The Unrecorded Hour")
    create(:character, story: story, fullname: "Odile Vance", is_protagonist: true)
    create(:location, story: story, name: "Ward Office 12")
    create(:location, story: story, name: "The Supply Closet")
    story
  end
end
