require "test_helper"

class Eval::Arrival::StageTest < ActiveSupport::TestCase
  test "all fixed branches render repeatable requests from records" do
    BaseAgent.stub(:new, ->(*) { raise "offline staging must not ask a model" }) do
      Eval::Arrival.cases.each do |kase|
        requests = 2.times.map do
          Eval::Arrival::Stage.open(kase) do |stage|
            prompt = stage.request.fetch("user")
            assert stage.room.realized?
            assert_includes stage.generator.characters_present, stage.player
            assert_nil stage.player.location
            assert_operator Character.present_in(stage.room).count, :<=, Character::Registry::MAX_PER_ROOM
            if kase["opening"]
              assert_equal stage.room, stage.story.opening_location
              assert_nil stage.generator.previous_scene
              assert_includes prompt, "Nothing. This is where the story opens."
              assert_equal stage.story.start_time, stage.generator.story_timestamp
              others = stage.generator.characters_present - [ stage.player ]
              kase["id"] == "opening_empty" ? assert_empty(others) : assert_predicate(others, :any?)
            end
            if kase["id"] == "returning"
              assert_includes prompt, "They were last here about 2 hours ago"
              assert stage.room.scenes.exists?
            end
            assert_includes prompt, "None written yet." if kase["id"] == "no_exits"
            assert_includes prompt, "Maren Vosk is badly hurt" if kase["id"] == "wounded_resident"
            assert_includes prompt, "You are carrying: brass key." if %w[carried_key floor_and_carried].include?(kase["id"])
            assert_includes prompt, "Dead here: Maren Vosk." if kase["id"] == "dead_resident"
            if %w[crossing_harm pending_toll].include?(kase["id"])
              stage.game.tolls.each do |toll|
                source = toll.location_connection || toll.location
                assert_equal source.hazard, toll.hazard
                assert source.hazardous?
                assert_includes prompt, Playthrough::Moment.new(stage.game).one_toll(toll)
              end
            end
            stage.request
          end
        end
        assert_equal(*requests)
      end
    end
  end

  test "study cases rebuild the retained candidate user and system bytes" do
    rows = JSON.parse(Eval::Arrival::STUDY.join("arrival-after.json").read).fetch("rows")
    rows.uniq { |r| r.fetch("case") }.each do |row|
      kase = Eval::Arrival.cases.find { |k| k["id"] == row["case"] }
      Eval::Arrival::Stage.open(kase) do |stage|
        assert_equal row.fetch("prompt"), stage.request.fetch("user")
        assert_equal row.fetch("instructions"), stage.request.fetch("system")
        assert_equal row.fetch("calls").first.fetch("schema"), stage.request.fetch("schema")
      end
    end
  end

  test "actual generator asks precisely the identity request once during offline replay" do
    previous_key = RubyLLM.config.openrouter_api_key
    RubyLLM.config.openrouter_api_key ||= "offline-arrival-test"
    Eval::Classifier::Arm.parse(Eval::Arrival.model).pinned do
      Eval::Arrival.cases.each do |kase|
        row = Eval::Arrival::Bench.new.read(kase, rep: 1,
          replay: { "description" => "You enter the room. Water laps below. The air is still.", "summary" => "Iri enters the room." })
        assert_nil row["error"], row["error"]
        assert_equal 1, row.fetch("requests").size
        assert_equal Eval::RequestIdentity.of(row.fetch("requests")), row.fetch("request_identity")
      end
    end
  ensure
    RubyLLM.config.openrouter_api_key = previous_key
  end
end
