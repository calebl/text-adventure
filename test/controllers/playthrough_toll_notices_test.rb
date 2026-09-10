require "test_helper"
require "turbo/broadcastable/test_helper"

class PlaythroughTollNoticesTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  QUIET_ARRIVAL = {
    "description" => "The counting house opens before you.",
    "summary" => "The crossing costs the player 3 hit points."
  }.freeze

  setup do
    @game = create(:playthrough, :started)
    @game.character.update!(level: 10, strength: nil, dexterity: nil, will: nil)
    @origin = @game.current_location
    @destination = create(:location, :flooded, story: @game.story, name: "Counting House")
    @edge = create(:location_connection, location: @origin, connected_location: @destination,
                                         distance: "adjacent", travel_method: "walking")
  end

  test "a quiet arrival description still shows the claimed harm with debug off" do
    agent = FakeAgent.new(QUIET_ARRIVAL)
    scene = Roll.stub(:die, 3) do
      BaseAgent.stub(:new, agent) { Playthrough::Turn.new(@game).play("/move Counting House") }
    end
    toll = @game.tolls.sole

    Playthrough::Debug.stub(:enabled?, false) { get playthrough_path(@game) }

    assert_response :success
    assert_select ".log .turn", text: QUIET_ARRIVAL.fetch("description")
    assert_select ".log .turn + .notice", text: toll.to_s, count: 1
    assert_select ".machinery", count: 0
    assert_not_includes response.body, QUIET_ARRIVAL.fetch("summary")
    assert_equal 3, toll.damage
    assert_equal scene, toll.scene
    assert_equal QUIET_ARRIVAL.fetch("description"), scene.reload.description
    assert_equal 1, agent.prompts.length
  end

  test "a shared opening shows only this game's claimed tolls" do
    opening = create(:scene, :opening, story: @game.story, location: @origin)
    @game.update!(current_scene: opening)
    other = create(:playthrough, story: @game.story, character: @game.character,
                                 current_location: @origin, current_scene: opening)
    mine = create(:playthrough_toll, playthrough: @game, scene: opening, hazard: "flooded")
    theirs = create(:playthrough_toll, playthrough: other, scene: opening, hazard: "unlit")
    unclaimed = create(:playthrough_toll, playthrough: @game, hazard: "silent", sequence: -2)

    Playthrough::Debug.stub(:enabled?, false) { get playthrough_path(@game) }

    assert_select ".log .notice", count: 1, text: mine.to_s
    assert_select "#playthrough_toll_#{theirs.id}", count: 0
    assert_select "#playthrough_toll_#{unclaimed.id}", count: 0
  end

  test "notices preserve saves, zero damage and death while escaping stored text" do
    scene = create(:scene, story: @game.story, location: @origin)
    @game.update!(current_scene: scene)
    saved = create(:playthrough_toll, :saved, playthrough: @game, scene: scene)
    zero = create(:playthrough_toll, playthrough: @game, scene: scene, damage: 0, sequence: -2)
    killed = create(:playthrough_toll, :killing, playthrough: @game, scene: scene,
                                              hazard: "<script>bad()</script>", sequence: -3)

    Playthrough::Debug.stub(:enabled?, false) { get playthrough_path(@game) }

    assert_select ".log .notice", count: 3
    assert_select "#playthrough_toll_#{saved.id}", text: /got clear of flooded/
    assert_select "#playthrough_toll_#{zero.id}", text: /0 hit points/
    assert_select "#playthrough_toll_#{killed.id}", text: killed.to_s
    assert_includes killed.to_s, "is dead"
    assert_select ".log .notice script", count: 0
    assert_includes response.body, "&lt;script&gt;bad()&lt;/script&gt;"
  end

  test "rendering a preloaded log reads no more body or doorway rows" do
    previous = nil
    3.times do
      scene = create(:scene, story: @game.story, location: @destination, previous_scene: previous)
      create(:playthrough_toll, playthrough: @game, scene: scene, location: @destination,
                               location_connection: @edge, hazard: "drop")
      previous = scene
    end
    @game.update!(current_scene: previous)
    turns = @game.reload.turn_log
    queries = []
    capture = ->(*args) { queries << args.last.fetch(:sql) unless args.last[:cached] || args.last[:name] == "SCHEMA" }
    rendered = nil

    Playthrough::Debug.stub(:enabled?, false) do
      ActiveSupport::Notifications.subscribed(capture, "sql.active_record") do
        rendered = ApplicationController.render(partial: "turns/turn", collection: turns, as: :turn,
                                                locals: { playthrough: @game })
      end
    end

    assert_empty queries
    assert_equal 3, Nokogiri::HTML.fragment(rendered).css(".notice").length
    assert_includes rendered, "the way from #{@origin.name} into Counting House"
  end

  test "redelivering a job shows one toll notice without another model call or charge" do
    streams = Playthrough::Debug.stub(:enabled?, false) do
      capture_turbo_stream_broadcasts(@game) do
        Roll.stub(:die, 3) do
          BaseAgent.stub(:new, FakeAgent.new(QUIET_ARRIVAL)) do
            NarrationJob.perform_now(@game.id, "/move Counting House", "arrival-form")
          end
        end
      end
    end
    toll = @game.tolls.sole
    assert_equal 1, streams.last.css("#playthrough_toll_#{toll.id}").length

    delivered = nil
    assert_no_difference [ "Playthrough::Toll.count", "Scene.count" ] do
      delivered = Playthrough::Debug.stub(:enabled?, false) do
        capture_turbo_stream_broadcasts(@game) do
          BaseAgent.stub(:new, ->(*) { flunk "redelivery must not ask a model" }) do
            NarrationJob.perform_now(@game.id, "/move Counting House", "arrival-form")
          end
        end
      end
    end

    assert_equal 1, delivered.length
    assert_equal 1, delivered.sole.css("#playthrough_toll_#{toll.id}").length
    assert_equal 1, delivered.sole.css(".log .notice").length
  end
end
