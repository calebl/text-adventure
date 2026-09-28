require "test_helper"

# THE ENGINE AGAINST ITS SPEC. docs/protocol/v1/openapi.json is what a client
# is written against and what a second engine would implement, so these check
# the engine against it: every route it draws under /api/v1 is in the spec
# and every path in the spec is drawn; the document is valid OpenAPI; the
# spec carries no engine type; and the panels come in their stated order.
# The shape of each response is checked where the response is made
# (`Api::V1Test`, `NarrationJobEventsTest`).
class ProtocolV1Test < ActionDispatch::IntegrationTest
  include ProtocolV1

  def drawn
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.sub("(.:format)", "")
      next unless path.start_with?("/api/v1")

      [ route.verb.downcase, path.gsub(/:(\w+)/) { "{#{Regexp.last_match(1).delete_suffix("_id").sub(/\Aid\z/, "game")}}" } ]
    end.to_set
  end

  def specified
    ProtocolV1.document["paths"].flat_map { |path, operations| operations.keys.map { |verb| [ verb, path ] } }.to_set
  end

  test "the document is valid OpenAPI 3.1" do
    assert_predicate ProtocolV1.openapi, :valid?, ProtocolV1.openapi.validate.to_a.first(3).inspect
  end

  test "every route under /api/v1 is in the spec, and every path in the spec is routed" do
    assert_equal specified, drawn
  end

  test "every event the engine writes has a schema, and the spec names no other" do
    assert_equal Playthrough::TurnEvent::KINDS.sort, ProtocolV1.document["x-events"].keys.sort
    ProtocolV1.document["x-events"].each_value { |name| assert ProtocolV1.document.dig("components", "schemas", name) }
  end

  test "every endpoint and every event kind carries an example, and each conforms to its schema" do
    ProtocolV1.document["paths"].each do |path, operations|
      operations.each do |verb, operation|
        operation["responses"].each do |status, response|
          response["content"].each_value { |content| assert content["examples"].present?, "#{verb} #{path} #{status}" }
        end
        assert operation.dig("requestBody", "content", "application/json", "examples").present?, "#{verb} #{path}" if operation["requestBody"]
      end
    end
    ProtocolV1.document["x-events"].each_key { |kind| assert ProtocolV1.event_example(kind), kind }

    ProtocolV1.examples.each do |pointer, value|
      next if pointer.include?("text~1event-stream")

      errors = ProtocolV1.openapi.ref(pointer).validate(value).map { |error| error["error"] }
      assert_empty errors, "the example at #{pointer} does not conform"
    end
  end

  test "the event stream's example is frames of the event examples" do
    stream = ProtocolV1.document.dig("paths", "/api/v1/games/{game}/turns/{turn}/events", "get", "responses", "200",
                                     "content", "text/event-stream", "examples", "example", "value")
    frames = sse_events(stream)
    assert_equal ProtocolV1.document["x-events"].keys.sort, frames.map { |frame| frame[:event] }.sort
    frames.each { |frame| assert_equal ProtocolV1.event_example(frame[:event]), frame[:data] }
  end

  test "the spec's closed lists are the engine's" do
    schemas = ProtocolV1.document.dig("components", "schemas")
    verbs = Playthrough::Availability.new(create(:playthrough)).verbs.map { |verb| verb.name.to_s }
    assert_equal verbs, schemas.dig("Verb", "properties", "name", "enum")
    assert_equal Playthrough::Refusal::KINDS.map(&:to_s),
                 schemas.dig("FinishedEvent", "properties", "refusal", "oneOf", 1, "properties", "kind", "enum")
    assert_equal Protocol::V1::OUTCOMES.sort, schemas.dig("FinishedEvent", "properties", "outcome", "properties", "kind", "enum").sort
    assert_equal Protocol::V1::CAPABILITIES, %w[worlds games turns turn_events interruptions spend_limit]
  end

  test "no framework, class or table name leaks into the spec" do
    text = ProtocolV1::DOCUMENT.read
    %w[Rails ActiveRecord Playthrough Scene Story Location Character Command ruby_llm sqlite].each do |word|
      assert_no_match(/\b#{word}\b/, text, "#{word} is an engine type, not a protocol word")
    end
  end

  test "the panels come in the order the engine recorded them, and the verbs in the enum's order" do
    player, token = Player.invite!("Ada")
    story = create(:story)
    here = create(:location, story: story, name: "Office")
    create(:character, story: story, fullname: "Zed Player", is_protagonist: true)
    ways = %w[Yard Annex Cellar].map { |name| create(:location, story: story, name: name) }
    ways.each do |way|
      create(:location_connection, location: here, connected_location: way, distance: "adjacent", travel_method: "walking")
      create(:location_connection, location: way, connected_location: here, distance: "adjacent", travel_method: "walking")
    end
    people = [ "Yves Last", "Ada First" ].map { |name| create(:character, story: story, fullname: name, location: here) }
    game = Playthrough::Session.begin!(story, player: player).playthrough
    lying = %w[zinc-cup brass-key].map { |name| lying_here(game, here, name: name) }
    carried = %w[wand apple].map { |name| create(:item, :carried, playthrough: game, name: name) }

    get api_v1_game_path(game.token), headers: { "Authorization" => "Bearer #{token}" }
    glance = JSON.parse(response.body)["glance"]
    assert_protocol "Glance", glance

    assert_equal ways.sort_by(&:id).map(&:name), glance["exits"].map { |exit| exit["name"] }
    assert_equal people.sort_by(&:id).map(&:fullname), glance["people"].map { |person| person["name"] }
    assert_equal lying.sort_by(&:id).map(&:name), glance["lying_here"].map { |item| item["name"] }
    assert_equal carried.sort_by(&:id).map(&:name), glance["carrying"].map { |item| item["name"] }
    assert_equal ProtocolV1.document.dig("components", "schemas", "Verb", "properties", "name", "enum"),
                 glance["verbs"].map { |verb| verb["name"] }
  end
end
