require "test_helper"

# EVERY NOUL QUESTION THE APP SENDS NAMES BOTH OF ITS ENDS.
#
# The provider refuses a Noul question whose `criteria` lacks a `true` or a
# `false` string, and it refuses the whole request with it -- so one empty
# criteria map turns every call that carries it into a 400 and hands the room
# back to the die without a single answer. The volition request shipped that
# way and nothing offline noticed, because its pinned fixture pinned the empty
# map along with everything else.
#
# So this builds each request the app sends, for a room with somebody and
# something in it, and checks every Noul question in it. The source scan at the
# bottom keeps the list of builders honest: a new file that writes a Noul
# question fails here until it is added above.
class SystemOneNoulCriteriaTest < ActiveSupport::TestCase
  BUILDERS = %w[
    app/models/playthrough/classifier/request.rb
    app/models/playthrough/volition/system_one.rb
  ].freeze

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
  end

  test "the classifier's Noul questions each carry a true and a false criterion" do
    state = Playthrough::Classifier::State.new(Playthrough::Classifier.new(@game), "take the brass ledger key")

    assert_both_ends Playthrough::Classifier::Request.new(state).to_h
  end

  test "the volition request's Noul questions each carry a true and a false criterion" do
    Playthrough::Volition.new(@game, @clerk, location: @room).apply!(Playthrough::Volition::WAIT)
    request = Playthrough::Volition::SystemOne.new(@game, [ @clerk ], location: @room, line: "read the docket").request

    assert_both_ends request[:questions]
  end

  test "no other file writes a Noul question" do
    writers = Dir[Rails.root.join("{app,lib}/**/*.rb")].select { |path| File.read(path).match?(/"type"\s*=>\s*"noul",\s*"instructions"/) }
    writers = writers.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }

    assert_equal BUILDERS.sort, writers.sort, "a new Noul question builder needs a case in this file"
  end

  private

  def assert_both_ends(questions)
    nouls = questions.select { |_id, question| question["type"] == "noul" }
    assert nouls.any?, "the request asked no Noul question, so this checked nothing"

    nouls.each do |id, question|
      criteria = question["criteria"]
      %w[true false].each do |end_|
        value = criteria.is_a?(Hash) ? criteria[end_] : nil
        assert value.is_a?(String) && value.strip.present?, "#{id} sends no #{end_.inspect} criterion: #{criteria.inspect}"
      end
    end
  end
end
