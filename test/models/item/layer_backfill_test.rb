require "test_helper"

# THE ONE-TIME SPLIT of a database written before the world was the template and
# the playthrough owned the instances.
#
# The four outcomes are the whole of the class and each one is a different claim
# about what the records can answer, so each gets its own test. So does the
# thing every backfill in this app has to be able to say for itself: that
# running it twice writes nothing the second time.
#
# Offline, deterministic, free -- nothing here calls a model.
class Item::LayerBackfillTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @protagonist = create(:character, :protagonist, story: @story, fullname: "Odile Vance")
    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
  end

  def run_backfill(dry_run: false, only: nil)
    Item::LayerBackfill.new(@story).run(dry_run: dry_run, only: only)
  end

  def answer_for(item, **options)
    run_backfill(**options).answers.find { |answer| answer.item.id == item.id }
  end

  # A playthrough standing somewhere, with the snapshot it would have taken
  # removed -- which is the state every database older than the layers is in.
  def unsnapshotted_playthrough(location: @office)
    playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: location)
    playthrough.items.destroy_all
    playthrough
  end

  # One turn of a playthrough's chain, recorded the way `Playthrough::Turn#play`
  # records it: what was typed, what it did, to which row, and where.
  def records_taking(playthrough, item, location: playthrough.current_location, at: 1.hour)
    scene = create(:scene, story: @story, location: location, previous_scene: playthrough.current_scene,
                           typed: "take the #{item.name}", resolved_action: "take", acted_on: item,
                           story_timestamp: @story.start_time + at)
    playthrough.update!(current_scene: scene)
    scene
  end

  # --- template: most of a database ----------------------------------------

  test "a row no turn log records taking is one of the world's own and is left alone" do
    stamp = create(:item, :lying, location: @office, name: "ward stamp")

    answer = answer_for(stamp)

    assert_predicate answer, :template?
    assert_equal @office, stamp.reload.location
    assert_predicate stamp, :template?
  end

  # --- attributed: the row a take moved ------------------------------------

  # THE WHOLE OF THE DEFECT, in one row. Before the layer split `take` moved the
  # world's only row out of the room, so the room was a thing poorer for
  # everybody. The row becomes that player's copy and the world gets its own row
  # back, in the room the take happened in.
  test "a row one playthrough's chain took becomes that playthrough's copy, and the world gets its row back" do
    playthrough = unsnapshotted_playthrough
    stamp = create(:item, :carried, playthrough: playthrough, name: "ward stamp")
    records_taking(playthrough, stamp, location: @office)

    answer = answer_for(stamp)

    assert_predicate answer, :attributed?
    assert_equal playthrough, answer.playthrough
    assert_equal @office, answer.location

    assert_predicate stamp.reload, :carried?
    assert_equal playthrough, stamp.playthrough
    assert_equal "ward stamp", stamp.template.name
    assert_equal @office, stamp.template.location
    assert_predicate stamp.template, :template?
  end

  # TAKEN THEN DROPPED SOMEWHERE ELSE. The row lies where that party left it and
  # it is still that party's; the world's own row goes back to where the take
  # happened, not to where the drop did.
  test "a row taken in one room and dropped in another keeps its place and restores the room it came from" do
    playthrough = unsnapshotted_playthrough
    stamp = create(:item, :lying, location: @closet, name: "ward stamp")
    records_taking(playthrough, stamp, location: @office)

    answer_for(stamp)

    assert_equal @closet, stamp.reload.location, "the player's copy lies where they left it"
    assert_equal playthrough, stamp.playthrough
    assert_equal @office, stamp.template.location, "the world's own row goes back where it was taken from"
  end

  # THE SHARED INVENTORY, WHICH IS ONE CASE OF THIS ONE. A row held by the
  # protagonist that a chain records taking was never the starting inventory:
  # it is that player's copy, and for an instance the protagonist's hands ARE
  # the party's hands.
  test "a row the protagonist holds that a chain took becomes that party's carried copy" do
    playthrough = unsnapshotted_playthrough
    stamp = create(:item, character: @protagonist, location: nil, name: "ward stamp")
    records_taking(playthrough, stamp, location: @office)

    answer_for(stamp)

    assert_predicate stamp.reload, :carried?
    assert_nil stamp.character_id
    assert_equal playthrough, stamp.playthrough
  end

  # A PR 111 CARRIED ROW WITH NO TAKE ON RECORD is a copy of the story's kit,
  # and the world's own row of that name is what it is a copy of.
  test "a copy of the starting kit is linked to the world's own row it came from" do
    daybook = create(:item, character: @protagonist, location: nil, name: "Ward Office 12 daybook")
    playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @office)
    copy = playthrough.carried.sole
    copy.update_columns(template_id: nil)

    answer = answer_for(copy)

    assert_predicate answer, :attributed?
    assert_equal daybook, copy.reload.template
    assert_predicate daybook.reload, :template?
  end

  # --- ambiguous: two chains, one moment ------------------------------------

  test "two chains taking one row at the same story moment is left alone and named" do
    first = unsnapshotted_playthrough
    second = unsnapshotted_playthrough
    stamp = create(:item, :lying, location: @office, name: "ward stamp")
    records_taking(first, stamp, at: 1.hour)
    records_taking(second, stamp, at: 1.hour)

    answer = answer_for(stamp)

    assert_predicate answer, :ambiguous?
    assert_equal [ first, second ].map(&:id).sort, answer.playthroughs.map(&:id).sort
    assert_predicate stamp.reload, :template?, "nothing is written when the records cannot choose"
  end

  # THE LATEST TAKE WINS when there is an order to choose from: an item was in
  # one place, so the last player to pick it up is the one who had it.
  test "two chains taking one row at different moments give it to the later one" do
    first = unsnapshotted_playthrough
    second = unsnapshotted_playthrough
    stamp = create(:item, :lying, location: @office, name: "ward stamp")
    records_taking(first, stamp, at: 1.hour)
    records_taking(second, stamp, at: 2.hours)

    answer = answer_for(stamp)

    assert_predicate answer, :attributed?
    assert_equal second, answer.playthrough
  end

  # --- unrecoverable: nothing says what it is a copy of ---------------------

  # LEFT WHERE IT IS AND NAMED. The row is a real thing that player really
  # holds; taking it off them to tidy the records is the one destructive thing
  # this could do.
  test "a copy nothing accounts for is left in that player's hands and reported" do
    playthrough = unsnapshotted_playthrough
    stray = create(:item, :carried, playthrough: playthrough, name: "a thing from nowhere")

    answer = answer_for(stray)

    assert_predicate answer, :unrecoverable?
    assert_predicate stray.reload, :carried?
    assert_equal playthrough, stray.playthrough
    assert_nil stray.template_id
  end

  # --- the snapshots every game is owed ------------------------------------

  test "every playthrough gets its copies of the rooms it has walked through" do
    create(:item, :lying, location: @office, name: "ward stamp")
    create(:item, :lying, location: @closet, name: "a private index")
    playthrough = unsnapshotted_playthrough(location: @closet)
    create(:scene, story: @story, location: @office, description: "a turn in the office").tap do |scene|
      playthrough.update!(current_scene: scene)
    end

    result = run_backfill

    snapshot = result.snapshots.sole
    assert_equal playthrough, snapshot.playthrough
    assert_equal [ "Ward Office 12", "The Supply Closet" ].sort, snapshot.rooms.map(&:name).sort
    assert_equal [ "a private index", "ward stamp" ], playthrough.items.order(:name).pluck(:name)
  end

  test "a room the game has never been in is not copied into it" do
    create(:item, :lying, location: @closet, name: "a private index")
    playthrough = unsnapshotted_playthrough(location: @office)

    run_backfill

    assert_empty playthrough.items_lying_in(@closet)
  end

  # --- the two rules every backfill in this app has to keep ------------------

  # AND THE DRY RUN HAS TO COUNT WHAT THE REAL RUN WOULD COPY, not what today's
  # rows say. The unlinked daybook below is the case that separates them: the
  # row phase links it, so the snapshot phase owes this party nothing -- and a
  # dry run that read the rows as they stand would promise a second daybook.
  test "a dry run writes nothing and reports the same figures the real run produces" do
    daybook = create(:item, character: @protagonist, location: nil, name: "Ward Office 12 daybook")
    playthrough = unsnapshotted_playthrough
    create(:item, :carried, playthrough: playthrough, name: daybook.name)
    stamp = create(:item, :carried, playthrough: playthrough, name: "ward stamp")
    records_taking(playthrough, stamp, location: @office)
    create(:item, :lying, location: @office, name: "a gas key")

    dry = run_backfill(dry_run: true)
    assert_nil stamp.reload.template_id, "a dry run wrote a template link"
    assert_empty playthrough.items_lying_in(@office), "a dry run handed out a copy"

    real = run_backfill
    assert_equal dry.answers.map(&:outcome), real.answers.map(&:outcome)
    assert_equal dry.snapshots.map { |row| row.copies.map(&:name).sort },
                 real.snapshots.map { |row| row.copies.map(&:name).sort }
  end

  # THE OTHER HALF OF THE SAME CLAIM. The row phase puts a world row back, and
  # every OTHER game that has been in that room is then owed a copy of it -- a
  # template that does not exist yet when the dry run is counting.
  test "a dry run counts the copies a restored world row will owe other games" do
    first = unsnapshotted_playthrough
    second = unsnapshotted_playthrough
    stamp = create(:item, :carried, playthrough: first, name: "ward stamp")
    records_taking(first, stamp, location: @office)

    dry = run_backfill(dry_run: true)
    real = run_backfill

    assert_equal dry.snapshots.map { |row| row.copies.map(&:name).sort },
                 real.snapshots.map { |row| row.copies.map(&:name).sort }
    assert_equal [ "ward stamp" ], second.items_lying_in(@office).pluck(:name)
    assert_empty first.items_lying_in(@office), "the player who took it is not owed a copy of it"
  end

  test "running it twice writes nothing the second time" do
    playthrough = unsnapshotted_playthrough
    stamp = create(:item, :carried, playthrough: playthrough, name: "ward stamp")
    records_taking(playthrough, stamp, location: @office)
    create(:item, :lying, location: @closet, name: "a private index")

    run_backfill

    assert_no_difference -> { Item.count } do
      second = run_backfill
      assert_predicate second, :nothing_to_do?
    end
  end

  # `Story::Repair` asks for one row's answer: a run repairing one finding must
  # not quietly re-furnish a whole story's rooms.
  test "only narrows the row phase to one item and takes no snapshots at all" do
    playthrough = unsnapshotted_playthrough
    stamp = create(:item, :carried, playthrough: playthrough, name: "ward stamp")
    records_taking(playthrough, stamp, location: @office)
    create(:item, :lying, location: @office, name: "a gas key")

    result = run_backfill(only: stamp.id)

    assert_equal [ stamp.id ], result.answers.map { |answer| answer.item.id }
    assert_empty result.snapshots
    assert_empty playthrough.items_lying_in(@office).by_name("a gas key")
  end
end
