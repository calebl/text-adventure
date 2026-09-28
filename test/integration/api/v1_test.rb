require "test_helper"

# THE ENGINE API FROM THE OUTSIDE: real requests, real tokens, every body
# validated against docs/protocol/v1. No model is called anywhere -- a turn is
# only accepted here, and `NarrationJobEventsTest` plays one with the fake.
class Api::V1Test < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ProtocolV1

  setup do
    Api::V1::TurnsController::RATE_STORE.clear
    @player, @token = Player.invite!("Ada")
    @world = create(:story, title: "The Ward", summary: "A hospital at night.")
    @room = create(:location, story: @world, name: "Ward Office 12")
    create(:character, story: @world, fullname: "Odile Vance", is_protagonist: true)
  end

  def auth(token = @token) = { "Authorization" => "Bearer #{token}" }
  def json = JSON.parse(response.body)

  def start_game(token = @token)
    post api_v1_games_path, params: { world: @world.id.to_s }, headers: auth(token), as: :json
    assert_response :created
    json.dig("game", "id")
  end

  # --- who is asking ---------------------------------------------------------

  test "no token, a wrong token and a revoked token are all the same 401" do
    get api_v1_service_path
    assert_response :unauthorized
    assert_protocol "Error", json
    assert_like_example ProtocolV1.example(:get, "/api/v1", 401), json
    assert_equal "unauthorized", json.dig("error", "code")

    get api_v1_service_path, headers: auth("not-a-token")
    assert_response :unauthorized
    wrong = response.body

    @player.revoke!
    get api_v1_service_path, headers: auth
    assert_response :unauthorized
    assert_equal wrong, response.body
  end

  test "the token never appears in a response or the log" do
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)
    begin
      get api_v1_service_path, headers: auth
      post api_v1_games_path, params: { world: "nope", token: @token }, headers: auth, as: :json
      get api_v1_service_path, headers: auth("#{@token}x")
    ensure
      Rails.logger.stop_broadcasting_to(logger)
    end
    assert_includes log.string, "Api::V1::GamesController", "the log was captured"
    assert_not_includes response.body, @token
    assert_not_includes log.string, @token
    assert_not Player.column_names.include?("token"), "only the digest is a column"
  end

  test "the parameter filter covers the token wherever it is sent" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal "[FILTERED]", filter.filter("token" => @token)["token"]
    assert_equal "[FILTERED]", filter.filter("request_token" => "x")["request_token"]
  end

  # --- the service -----------------------------------------------------------

  test "GET /api/v1 states the protocol, the engine and the player's spend" do
    get api_v1_service_path, headers: auth
    assert_response :ok
    assert_protocol "Service", json
    assert_like_example ProtocolV1.example(:get, "/api/v1", 200), json
    assert_equal 1, json["version"]
    assert_includes json["capabilities"], "turn_events"
    assert_equal ActiveRecord::Base.connection_pool.migration_context.current_version.to_s, json["world_schema"]
    assert_equal 1.0, json.dig("player", "spend", "limit_usd")
    assert_equal 0.03, json.dig("player", "spend", "turn_reservation_usd")
  end

  test "worlds lists only the playable ones" do
    create(:story, title: "No one to play") { |story| create(:location, story: story) }
    get api_v1_worlds_path, headers: auth
    assert_response :ok
    assert_protocol "WorldList", json
    assert_like_example ProtocolV1.example(:get, "/api/v1/worlds", 200), json
    assert_equal [ "The Ward" ], json["worlds"].map { |world| world["title"] }
  end

  # --- games ---------------------------------------------------------------

  test "starting a game answers the whole screen and files it under the player" do
    post api_v1_games_path, params: { world: @world.id.to_s }, headers: auth, as: :json
    assert_response :created
    assert_protocol "Screen", json
    assert_like_example ProtocolV1.example(:post, "/api/v1/games", 201), json
    assert_equal "Ward Office 12", json.dig("glance", "room", "name")
    assert_equal @player, Playthrough.find_by!(token: json.dig("game", "id")).player

    get api_v1_game_path(json.dig("game", "id")), headers: auth
    assert_response :ok
    assert_protocol "Screen", json
    assert_like_example ProtocolV1.example(:get, "/api/v1/games/{game}", 200), json

    get api_v1_games_path, headers: auth
    assert_protocol "GameList", json
    assert_like_example ProtocolV1.example(:get, "/api/v1/games", 200), json
    assert_equal 1, json["games"].size
  end

  test "an unplayable world is refused with the engine's sentence" do
    bare = create(:story, title: "Empty")
    post api_v1_games_path, params: { world: bare.id.to_s }, headers: auth, as: :json
    assert_response :unprocessable_content
    assert_protocol "Error", json
    assert_equal "unplayable", json.dig("error", "code")
    assert_like_example ProtocolV1.example(:post, "/api/v1/games", 422), json
  end

  test "a player cannot be assigned by a parameter" do
    other, = Player.invite!("Grace")
    post api_v1_games_path, params: { world: @world.id.to_s, player_id: other.id, player: { id: other.id } },
                            headers: auth, as: :json
    assert_equal @player, Playthrough.find_by!(token: json.dig("game", "id")).player
  end

  # --- another player's games -----------------------------------------------

  test "another player's game is not found by any endpoint" do
    theirs = start_game
    command = Playthrough.find_by!(token: theirs).commands.create!(command: "/look", request_token: "t")
    _intruder, token = Player.invite!("Mallory")

    get api_v1_game_path(theirs), headers: auth(token)
    assert_response :not_found
    assert_like_example ProtocolV1.example(:get, "/api/v1/games/{game}", 404), json
    missing = response.body
    get api_v1_game_path("no-such-game"), headers: auth(token)
    assert_equal missing, response.body, "a foreign id and a made-up id cannot be told apart"

    assert_no_enqueued_jobs do
      post api_v1_game_turns_path(theirs), params: { line: "/look" }, headers: auth(token), as: :json
    end
    assert_response :not_found
    get api_v1_game_turn_events_path(theirs, command.id), headers: auth(token)
    assert_response :not_found
    post api_v1_game_acknowledge_interruption_path(theirs, command.id), headers: auth(token)
    assert_response :not_found
    assert_equal 1, Playthrough::Command.count
  end

  test "a browser game that belongs to nobody is not reachable either" do
    browser = create(:playthrough, story: @world, current_location: @room)
    get api_v1_game_path(browser.token), headers: auth
    assert_response :not_found
  end

  # --- turns ---------------------------------------------------------------

  test "a line is accepted and handed to the job with the event adapter" do
    game = start_game
    playthrough = Playthrough.find_by!(token: game)
    assert_enqueued_with job: NarrationJob, args: [ playthrough.id, "look around", "tok-1", "events" ] do
      post api_v1_game_turns_path(game), params: { line: "  look around ", request_token: "tok-1" }, headers: auth, as: :json
    end
    assert_response :accepted
    assert_protocol "TurnAccepted", json
    assert_like_example ProtocolV1.example(:post, "/api/v1/games/{game}/turns", 202), json
  end

  test "a blank line is not a turn" do
    game = start_game
    assert_no_enqueued_jobs do
      post api_v1_game_turns_path(game), params: { line: "   " }, headers: auth, as: :json
    end
    assert_response :unprocessable_content
    assert_equal "blank_line", json.dig("error", "code")
    assert_like_example ProtocolV1.example(:post, "/api/v1/games/{game}/turns", 422), json
  end

  test "at the limit a turn is refused with 402, nothing is written or enqueued, and reads still work" do
    game = start_game
    @player.update!(monthly_limit_usd: BigDecimal("0.05"))
    create(:system_one_receipt, player: @player, cost_usd: BigDecimal("0.03"))

    assert_no_difference -> { Playthrough::Command.count } do
      assert_no_enqueued_jobs do
        BaseAgent.stub(:new, ->(*) { flunk "a refused turn called a model" }) do
          post api_v1_game_turns_path(game), params: { line: "/look" }, headers: auth, as: :json
        end
      end
    end
    assert_response :payment_required
    assert_protocol "Error", json
    assert_equal "limit_reached", json.dig("error", "code")
    assert_like_example ProtocolV1.example(:post, "/api/v1/games/{game}/turns", 402), json
    assert_includes json.dig("error", "message"), "allowance is used up"

    get api_v1_game_path(game), headers: auth
    assert_response :ok
    get api_v1_service_path, headers: auth
    assert_response :ok
  end

  test "retrying the same request token past the limit cannot slip a second turn in" do
    game = start_game
    @player.update!(monthly_limit_usd: BigDecimal("0.03"))
    post api_v1_game_turns_path(game), params: { line: "/look", request_token: "once" }, headers: auth, as: :json
    assert_response :accepted
    post api_v1_game_turns_path(game), params: { line: "/look", request_token: "twice" }, headers: auth, as: :json
    assert_response :payment_required
    assert_equal 1, Playthrough::Command.count
  end

  test "the eleventh turn in a minute is rate limited" do
    game = start_game
    @player.update!(monthly_limit_usd: 100)
    10.times do |n|
      post api_v1_game_turns_path(game), params: { line: "/look", request_token: "r#{n}" }, headers: auth, as: :json
      assert_response :accepted
    end
    post api_v1_game_turns_path(game), params: { line: "/look", request_token: "r10" }, headers: auth, as: :json
    assert_response :too_many_requests
    assert_protocol "Error", json
    assert_equal "rate_limited", json.dig("error", "code")
    assert_like_example ProtocolV1.example(:post, "/api/v1/games/{game}/turns", 429), json
  end

  # --- events --------------------------------------------------------------

  test "a finished turn replays whole and resumes after Last-Event-ID" do
    game = start_game
    command = Playthrough.find_by!(token: game).commands.create!(command: "/look", request_token: "t", status: "completed")
    Playthrough::TurnEvent.append!(command, "started", { turn: command.id.to_s, line: "/look" })
    Playthrough::TurnEvent.append!(command, "prose", { turn: command.id.to_s, text: "A desk. " })
    Playthrough::TurnEvent.append!(command, "prose", { turn: command.id.to_s, text: "A lamp." })
    Playthrough::TurnEvent.append!(command, "finished", { turn: command.id.to_s })

    get api_v1_game_turn_events_path(game, command.id), headers: auth
    assert_response :ok
    assert_equal "text/event-stream", response.media_type
    assert_equal [ 1, 2, 3, 4 ], sse_events(response.body).map { |event| event[:id] }

    get api_v1_game_turn_events_path(game, command.id), headers: auth.merge("Last-Event-ID" => "2")
    assert_equal [ [ 3, "prose" ], [ 4, "finished" ] ], sse_events(response.body).map { |event| [ event[:id], event[:event] ] }

    get api_v1_game_turn_events_path(game, command.id, last_event_id: 3), headers: auth
    assert_equal [ "finished" ], sse_events(response.body).map { |event| event[:event] }
  end

  test "a turn still running is tailed until it finishes" do
    game = start_game
    command = Playthrough.find_by!(token: game).commands.create!(command: "/look", request_token: "t")
    Playthrough::TurnEvent.append!(command, "started", { turn: command.id.to_s, line: "/look" })
    writer = Thread.new do
      sleep 0.3
      Playthrough::TurnEvent.append!(command, "prose", { turn: command.id.to_s, text: "Later." })
      Playthrough::TurnEvent.append!(command, "finished", { turn: command.id.to_s })
    end

    get api_v1_game_turn_events_path(game, command.id), headers: auth
    writer.join
    assert_equal %w[started prose finished], sse_events(response.body).map { |event| event[:event] }
  end

  test "a resume id cannot reach another turn's or another player's events" do
    game = start_game
    mine = Playthrough.find_by!(token: game).commands.create!(command: "/look", request_token: "a")
    Playthrough::TurnEvent.append!(mine, "finished", { turn: mine.id.to_s })
    other = create(:playthrough_command)
    Playthrough::TurnEvent.append!(other, "prose", { text: "someone else's" })
    Playthrough::TurnEvent.append!(other, "finished", {})

    get api_v1_game_turn_events_path(game, other.id), headers: auth.merge("Last-Event-ID" => "0")
    assert_response :not_found
    get api_v1_game_turn_events_path(game, mine.id), headers: auth.merge("Last-Event-ID" => "0")
    assert_not_includes response.body, "someone else's"
  end

  test "a busy game names the turn in hand, and its events are reachable by that id" do
    game = start_game
    assert_nil json.dig("standing", "running_turn")
    post api_v1_game_turns_path(game), params: { line: "/look", request_token: "busy-1" }, headers: auth, as: :json
    turn = json.dig("turn", "id")

    get api_v1_game_path(game), headers: auth
    assert_protocol "Screen", json
    assert_equal [ true, turn ], [ json.dig("standing", "busy"), json.dig("standing", "running_turn") ]

    command = Playthrough.find_by!(token: game).commands.find(turn)
    Playthrough::TurnEvent.append!(command, "started", { turn: turn, line: "/look" })
    Playthrough::TurnEvent.append!(command, "finished", { turn: turn })
    get api_v1_game_turn_events_path(game, json.dig("standing", "running_turn")), headers: auth
    assert_response :ok
    assert_equal %w[started finished], sse_events(response.body).map { |event| event[:event] }

    _other, token = Player.invite!("Grace")
    get api_v1_game_turn_events_path(game, turn), headers: auth(token)
    assert_response :not_found
  end

  test "the glance names each verb's word, and a use line sent as given is the attempt it names" do
    game = start_game
    playthrough = Playthrough.find_by!(token: game)
    create(:item, :carried, playthrough: playthrough, name: "flask of water", use_kind: "drink")
    get api_v1_game_path(game), headers: auth
    verbs = json.dig("glance", "verbs").index_by { |verb| verb["name"] }
    assert_equal "go", verbs.dig("move", "word")
    assert_equal "inspect", verbs.dig("examine", "word")
    assert_nil verbs.dig("take", "lines")

    use = verbs.fetch("use")
    assert_equal [ "Consume flask of water" ], use["targets"]
    assert_equal [ "/consume flask of water" ], use["lines"]
    choice = Playthrough::Availability.new(playthrough.reload).verb(:use).targets.first
    assert_equal choice.token, Playthrough::Grammar.new(playthrough).reading_first(use["lines"].first).intent.physical.token
  end

  # --- interruptions -------------------------------------------------------

  test "acknowledging a legacy interruption answers the standing" do
    game = start_game
    stuck = Playthrough.find_by!(token: game).commands.create!(command: "/look", request_token: "old", status: "running")
    get api_v1_game_path(game), headers: auth
    assert_equal({ "turn" => stuck.id.to_s, "line" => "/look", "request_token" => "old", "action" => "acknowledge" },
                 json.dig("standing", "saved_turn"))

    post api_v1_game_acknowledge_interruption_path(game, stuck.id), headers: auth
    assert_response :ok
    assert_protocol "StandingResponse", json
    assert_like_example ProtocolV1.example(:post, "/api/v1/games/{game}/interruptions/{turn}/acknowledge", 200), json
    assert_nil json.dig("standing", "saved_turn")
    assert_equal "interruption_acknowledged", stuck.reload.error_kind
  end
end
