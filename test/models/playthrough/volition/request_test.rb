require "test_helper"

# THE TYPED VOLITION REQUEST, WITH NO MODEL CALL ANYWHERE IN IT.
#
# The request is the engine's (`volition::request`, through
# `Playthrough::Requests`): what a turn the game plays asks System One about
# who in a room does what. Its exact bytes for one staged room are pinned
# (`test/fixtures/files/volition_system_one_request.json`, rewritten only when
# the request is meant to change), because `rake eval:volition_probe` sends
# that file and nothing else. How an answer becomes an act is the engine's
# too, and is held there; the Ruby reference loop the suite plays asks nobody.
class Playthrough::Volition::RequestTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test/fixtures/files/volition_system_one_request.json")

  setup do
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Counting Room")
    @next_door = create(:location, story: @story, name: "The Stairwell")
    create(:location_connection, location: @room, connected_location: @next_door)
    create(:location_connection, location: @next_door, connected_location: @room)
    @player = create(:character, :protagonist, story: @story)
    @game = create(:playthrough, story: @story, character: @player, current_location: @room)
    @clerk = create(:character, :driven, story: @story, location: @room, fullname: "Odile Vance", nickname: "Odile")
    create(:item, character: nil, location: @room, playthrough: @game, name: "a brass ledger key")
    Playthrough::Volition.new(@game, @clerk, location: @room).apply!(Playthrough::Volition::WAIT)
  end

  def request
    Playthrough::Requests.build(:volition, playthrough: @game.id, characters: [ @clerk.id ], location: @room.id,
                                           line: "read the docket")
  end

  test "the request is byte for byte the pinned one" do
    assert_equal FIXTURE.read, "#{JSON.pretty_generate(request)}\n"
  end

  test "the request names no row id, so it is the same whatever ids the rows got" do
    json = request.to_json

    [ @room, @next_door, @clerk ].each { |row| assert_not_includes json, ":#{row.id}\"" }
  end

  test "the reference loop asks nobody and the die decides, with a plain receipt" do
    SystemOneAgent.stub(:configured?, true) do
      SystemOneAgent.stub(:new, ->(*) { flunk "the reference loop asked System One" }) do
        assert_equal 1, Playthrough::Volition.run!(@game, location: @room, line: "read the docket").size
      end
    end
    row = @game.volitions.where(character: @clerk).order(:id).last

    assert_equal Playthrough::Volition::DECIDED_BY_DIE, row.decided_by
    assert_nil row.system_one_error
  end
end
