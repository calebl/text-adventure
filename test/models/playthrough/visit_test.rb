require "test_helper"

# `Playthrough::Visit` is the record of every room one game has stood in: taken
# wherever a room is snapshotted, and after every line the Rust engine plays.
# `Story::Doctor` reads it, so an offline walk -- which writes no `Scene` -- is
# still a walk.
class Playthrough::VisitTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @court = create(:location, story: @story, name: "The Causeway Court")
    @post = create(:location, story: @story, name: "The Tide Post")
    [ [ @court, @post ], [ @post, @court ] ].each do |from, to|
      create(:location_connection, location: from, connected_location: to, distance: "adjacent", travel_method: "walking")
    end
    @game = create(:playthrough, story: @story, character: create(:character, :protagonist, story: @story),
                                 current_location: @court)
  end

  test "a new game has stood in the room it opens in" do
    assert_equal [ @court ], @game.visits.map(&:location)
  end

  test "a room is stood in once however often it is walked back into" do
    assert_no_difference -> { Playthrough::Visit.count } do
      Playthrough::Visit.record!(@game, @court)
      Playthrough::Snapshot.new(@game).of_the_room!(@court)
    end
    assert_not build(:playthrough_visit, playthrough: @game, location: @court).valid?
    assert build(:playthrough_visit, playthrough: create(:playthrough, story: @story), location: @court).valid?
  end

  test "standing nowhere records nothing, and another world's room is refused" do
    assert_nil Playthrough::Visit.record!(@game, nil)
    assert_not build(:playthrough_visit, playthrough: @game, location: create(:location)).valid?
  end

  test "an offline move records the room it stands the party in" do
    BaseAgent.stub(:new, ->(*) { raise "an offline move made a model call" }) do
      Playthrough::Mechanics.new(@game, model: false).run("/go tide post")
    end

    assert_equal [ @court, @post ], @game.visits.order(:id).map(&:location)
  end

  # The engine writes the move on a connection of its own and knows nothing of
  # this table; the visit is taken from where it left the party.
  test "a line the Rust engine plays records the room it left the party in" do
    game = @game
    post = @post
    engine = Module.new do
      define_singleton_method(:play) do |_database, _id, _line, _decision|
        Playthrough.where(id: game.id).update_all(current_location_id: post.id)
        { "report" => { "change" => "moved" } }.to_json
      end
    end

    Playthrough::RustEngine.stub(:extension, engine) { Playthrough::RustEngine.play(game, "/go tide post") }

    assert_includes game.visits.map(&:location), @post
  end

  test "a visit goes with the game and with the room" do
    Playthrough::Visit.record!(@game, @post)
    @post.destroy!
    assert_equal [ @court ], @game.visits.reload.map(&:location)

    @game.destroy!
    assert_empty Playthrough::Visit.where(playthrough_id: @game.id)
  end
end
