require "test_helper"

# THE CLASSIFIER BENCH'S REQUEST IDENTITY: the engine's classifier request for
# the corpus's designated line, its physical tokens normalized to the names they
# bind, in each request shape the bench can send.
class Eval::Classifier::VersionTest < ActiveSupport::TestCase
  test "identity is deterministic and notices instructions and closed labels" do
    before = Eval::Classifier::Version.offline
    assert_equal before, Eval::Classifier::Version.offline
    details = Eval::Classifier::Version.offline_details
    assert_equal before, details[:request_identity]
    assert_predicate details[:prompt_digest], :present?
    assert_predicate details[:instructions_digest], :present?

    requests = Eval::Classifier::Version.requests
    id, request = requests.first
    assert_equal before, Eval::Classifier::Version.identity(requests)
    refute_equal before, Eval::Classifier::Version.identity(id => request.merge(system: "#{request[:system]} Changed."))
    labels = JSON.parse(JSON.generate(request[:schema]))
    labels["schema"]["properties"]["target"]["enum"] << "a changed closed label"
    refute_equal before, Eval::Classifier::Version.identity(id => request.merge(schema: labels))
  end

  # THE GAP THE REPORT NAMED: a request identity keyed on `schema` alone would
  # go BLANK for a shape whose closed set lives in `tools` instead. Proved here
  # rather than assumed: the digest differs by shape, and a change reaching
  # only INSIDE a tool's parameters -- not its name, not its description --
  # still moves it.
  test "the request identity notices a tool shape, and a change inside a tool's own parameters" do
    schema_identity = Eval::Classifier::Version.offline(shape: :schema)
    single_identity = Eval::Classifier::Version.offline(shape: :tool)
    per_intent_identity = Eval::Classifier::Version.offline(shape: :tools)

    refute_equal schema_identity, single_identity
    refute_equal schema_identity, per_intent_identity
    refute_equal single_identity, per_intent_identity
    assert_equal single_identity, Eval::Classifier::Version.offline(shape: :tool),
                 "the same shape on the same corpus is deterministic"

    built, room = built_and_room(physical_game, "Wait 12 minutes.")
    widened = JSON.parse(JSON.generate(built))
    widened["schema"]["schema"]["properties"]["target"]["enum"] << "a changed closed label"
    refute_equal Eval::Classifier::Version.request_for(built, room, shape: :tool),
                 Eval::Classifier::Version.request_for(widened, room, shape: :tool),
                 "a changed enum reaches shape B through the schema it wraps"
    moved = room.merge("exits" => room.fetch("exits") + [ "a changed closed label" ])
    refute_equal Eval::Classifier::Version.request_for(built, room, shape: :tools),
                 Eval::Classifier::Version.request_for(built, moved, shape: :tools),
                 "and shape C's own tools are built from the room's own sets"
  end

  test "the request is the engine's classifier call, physical tokens included" do
    game = physical_game
    built, room = built_and_room(game, "Offer the apple to Maren.")
    request = Eval::Classifier::Version.request_for(built, room)
    enum = request.fetch(:schema).dig("schema", "properties", "target", "enum")
    tokens = room.fetch("physical").map { |choice| choice.fetch("token") }

    assert_predicate tokens, :any?
    tokens.each { |token| assert_includes enum, token }
    assert_includes request[:user], tokens.last
    assert_equal Playthrough::Classifier::INSTRUCTIONS, request[:system]
  end

  test "only known list and schema token IDs normalize while complete bindings stay visible" do
    first = physical_game
    second = physical_game
    rooms = [ first, second ].map { |game| built_and_room(game, "Wait 12 minutes.") }
    refute_equal(*rooms.map { |_, room| room.fetch("physical").map { |choice| choice.fetch("token") } })
    raw = rooms.map { |built, room| Eval::Classifier::Version.request_for(built, room) }
    normalized = rooms.each_with_index.map do |(_, room), index|
      Eval::Classifier::Version.normalize(raw[index], room.fetch("physical"))
    end
    assert_equal normalized.first, normalized.last
    assert_includes normalized.first[:user], "Wait 12 minutes."
    assert_includes normalized.first[:user], "Maren"

    choices = rooms.first.last.fetch("physical")
    token = choices.first.fetch("token")
    quoted = raw.first.merge(user: raw.first[:user] + "The player quotes #{token}.\n")
    assert_includes Eval::Classifier::Version.normalize(quoted, choices)[:user], "quotes #{token}."
    typed = "#{token}: A line which looks exactly like a listed choice."
    literal = Eval::Classifier::Version.request_for(*built_and_room(first, typed))
    assert_includes Eval::Classifier::Version.normalize(literal, choices)[:user], "## The Player Types\n#{typed}\n"
    described = raw.first.merge(schema: { description: token, enum: [ token ] })
    normalized_schema = Eval::Classifier::Version.normalize(described, choices)[:schema]
    assert_equal token, normalized_schema[:description]
    refute_equal [ token ], normalized_schema[:enum]
    unknown = raw.first.deep_dup
    unknown[:user] += "use:consume:999999:0:0:0: A different listed action.\n"
    refute_equal normalized.first, Eval::Classifier::Version.normalize(unknown, choices)

    second.story.characters.find_by!(fullname: "Maren").update!(fullname: "Ada")
    built, room = built_and_room(second, "Wait 12 minutes.")
    changed = Eval::Classifier::Version.request_for(built, room)
    refute_equal normalized.first, Eval::Classifier::Version.normalize(changed, room.fetch("physical"))
  end

  private

  def built_and_room(game, line)
    rows = Playthrough::Requests.rows
    [ Playthrough::Requests.build(:classifier, rows: rows, playthrough: game.id, line: line),
      Playthrough::Requests.build(:room, rows: rows, playthrough: game.id) ]
  end

  def physical_game
    story = create(:story)
    room = create(:location, story: story, name: "Ward Office 12")
    player = create(:character, :protagonist, story: story, fullname: "Cal")
    create(:character, story: story, location: room, fullname: "Maren", nickname: "Maren")
    game = create(:playthrough, story: story, character: player, current_location: room)
    create(:item, :carried, playthrough: game, name: "apple", use_kind: "food")
    game
  end
end
