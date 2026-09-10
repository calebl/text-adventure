require "test_helper"

class Eval::Realization::BranchesTest < ActiveSupport::TestCase
  test "branch staging renders requests while the legacy prompt and system identities stay fixed" do
    legacy = Eval::Realization::Version.offline
    assert_equal "08d08a01235d89d3", legacy[:prompt_digest]
    assert_equal "d43b9ecd17181013", legacy[:instructions_digest]
    assert_not_equal "8a06d8d919582e15", Eval::Realization.digest

    requests = Eval::Realization::BranchRequests.offline
    assert_equal requests, Eval::Realization::BranchRequests.offline
    %w[PLACE PERSON THING].zip(%w[reach-location speak-to hold-item]).each do |kind, id|
      prompt = requests.fetch("branch-quest-#{id}").fetch("user")
      assert_includes prompt, "needs a #{kind}"
      assert_includes prompt, "next: Recover the missing customs record."
      assert_includes prompt, "Do not bend"
    end
    assert_includes requests.fetch("branch-named-siblings").fetch("user"), "already named, so do not reuse one:"
    assert_includes requests.fetch("branch-saturated-items").fetch("user"), "Do not list any items:"
    assert_includes requests.fetch("branch-geometry-stairs").fetch("user"), "door in the east wall"
    assert_includes requests.fetch("branch-geometry-stairs").fetch("user"), "a stair up"
    assert Eval::Realization.unavailable_to_a_realization?(:door_in_a_wall_the_records_do_not_hold)
  end

  test "restoration identity includes the exact structured accepted detail and detects its loss" do
    request = Eval::Realization::BranchRequests.offline.fetch("branch-restored-conversation")
    history = request.fetch("history")
    assert_equal %w[user assistant], history.map { |message| message.fetch("role") }
    assert_equal branch("restored-conversation").staging.fetch("retry_detail"), JSON.parse(history.last.fetch("content"))
    assert_not_equal identity(request), identity(request.merge("history" => []))
    assert_not_equal identity(request), identity(request.merge("schema" => {}))
  end

  test "each quest target is admitted through the existing engine writer in an interior room" do
    { "reach-location" => "Location", "speak-to" => "Character", "hold-item" => "Item" }.each do |kind, type|
      stage("quest-#{kind}") do |standing|
        generator = standing.generator
        wanted = standing.kase.staging.fetch("quest").fetch("target_name")
        detail = { "description" => "A room where customs records are kept.", "lore" => "Clerks work here.",
                   "people" => [], "items" => [] }
        case type
        when "Location" then detail["name"] = wanted
        when "Character"
          detail["people"] = [ Character::Registry::SHEET.to_h { |field| [ field.to_s, "Keeps the customs records." ] }
                                .merge("fullname" => wanted, "nickname" => "Mara") ]
        when "Item" then detail["items"] = [ { "name" => wanted, "description" => "A portable customs docket." } ]
        end
        generator.stub(:ask, detail) { generator.write_detail! }
        step = standing.story.main_quest.steps.first
        assert step.bound?, kind
        assert_equal type, step.target_type
        target_room = type == "Location" ? step.target : step.target.location
        assert_equal standing.location.id, target_room.id
        assert target_room.parent_location_id
      end
    end
  end

  test "saturated world templates are retained and over-allowance proposals are refused" do
    stage("saturated-items") do |standing|
      assert_equal 0, standing.item_allowance
      assert standing.location.items.all?(&:template?)
      standing.generator.registry.admit!([ { "name" => "extra docket", "description" => "A customs docket." } ])
      assert_not standing.location.items.exists?(name: "extra docket")
      row = { "facts" => { "item_allowance" => 0 }, "answers" => { "detail" => {
        "items" => [ { "name" => "extra docket" } ] } }, "after" => { "items" => standing.location.items.pluck(:name) } }
      scorer = Eval::Realization::Scorer.new([ row ])
      assert_equal 1, scorer.flagged_for(:item_over_the_allowance).size
      assert_equal 1, scorer.flagged_for(:proposal_refused).size
    end
  end

  test "quest admission reads binding and older rows never earn its denominator" do
    row = { "facts" => { "quest_request" => { "trigger_kind" => "hold_item" } }, "after" => { "quest_admitted" => false } }
    scorer = Eval::Realization::Scorer.new([ row, {} ])
    assert_equal 1, scorer.judgeable_for(:quest_target_not_admitted)
    assert_equal 1, scorer.flagged_for(:quest_target_not_admitted).size
    row["after"]["quest_admitted"] = true
    assert_empty Eval::Realization::Scorer.new([ row ]).flagged_for(:quest_target_not_admitted)
  end

  test "the resumed reading buys only exits and keeps full replayed input" do
    stage("restored-conversation") do |standing|
      exits = { "exits" => [ { "name" => "Harbour Lane", "teaser" => "A lane beside the quay.",
                              "distance" => "a short walk", "travel_method" => "walking",
                              "inside" => "no inside", "population" => "nobody" } ] }
      reading = OfflineExchange.with(exits) do
        Eval::Realization::Bench.new.build(standing.kase, standing,
                                           Eval::Classifier::Arm.parse("ollama:#{OfflineExchange::MODEL[:model]}"), 1)
      end
      assert_nil reading.error
      assert_equal 1, reading.calls
      assert_equal 120, reading.input_tokens
      assert_equal 40, reading.output_tokens
      assert_equal [ "exits" ], reading.answers.keys
      assert_equal 1, reading.facts.fetch("requests").size
      assert_equal %w[user assistant], reading.facts.fetch("requests").first.fetch("history").map { |message| message.fetch("role") }
      scorer = Eval::Realization::Scorer.new([ reading.to_h.deep_stringify_keys ])
      assert_equal 1, scorer.scanned
      assert_equal 1, scorer.judgeable_for(:exit_over_the_allowance)
      assert_equal 0, scorer.judgeable_for(:item_over_the_allowance)
    end
  end

  test "the admission receipt follows the requested beat after an earlier bound beat" do
    stage("quest-hold-item") do |standing|
      quest = standing.story.main_quest
      quest.steps.first.update!(position: 2)
      previous = quest.steps.create!(position: 1, trigger_kind: "reach_location", summary: "Reach the quay.",
                                     target_name: "The Quay")
      previous.bind!(standing.story.locations.find_by!(name: "The Quay"), at: standing.story.start_time)
      detail = { "description" => "Clerks keep customs records here.", "lore" => "The room serves the quay.",
                 "people" => [], "items" => [] }
      detail["people"] = Array.new(standing.people_allowance) do |index|
        Character::Registry::SHEET.to_h { |field| [ field.to_s, "Keeps the customs records." ] }
          .merge("fullname" => "Customs clerk #{index}", "nickname" => "Clerk #{index}")
      end
      reading = OfflineExchange.with(detail) do
        Eval::Realization::Bench.new.build(standing.kase, standing,
                                           Eval::Classifier::Arm.parse("ollama:#{OfflineExchange::MODEL[:model]}"), 1)
      end
      assert_nil reading.error
      assert_equal "hold_item", reading.facts.fetch("quest_request").fetch("trigger_kind")
      assert_equal true, reading.after.fetch("quest_bound"), "the deadline supplies the omitted target"
      assert_equal false, reading.after.fetch("quest_admitted"), "the model must not get credit for the fallback"
      assert_equal false, Eval::Realization::Admissions.replay(reading.to_h.deep_stringify_keys)
    end
  end

  private

  def branch(suffix) = Eval::Realization.corpus.cases.find { |kase| kase.id == "branch-#{suffix}" }
  def stage(suffix, &block)
    kase = branch(suffix)
    Eval::Realization::Stage.open([ kase ]) { |stages| block.call(stages.fetch(kase.id)) }
  end
  def identity(request) = Eval::Realization::BranchRequests.identity(request)
end
