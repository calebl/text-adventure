require "test_helper"
require "timeout"

# Real worker processes, committed fixtures and actual file/SQLite locks.
# A render is held at the provider boundary while a second worker attempts the
# same game. Ordinary transactional fixtures would hide the rows from workers
# and hold the writer themselves, defeating both assertions this test makes.
class Playthrough::TurnConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @game = create(:playthrough, :started)
    @story = @game.story
    @opening = create(:scene, story: @story, location: @game.current_location)
    @game.update!(current_scene: @opening)
    @children = []
    @pipes = []
    @models = RubyLLM::ActiveRecord::Model.pluck(:id)
  end

  teardown do
    @children.each do |pid|
      next unless Process.waitpid(pid, Process::WNOHANG).nil?

      Process.kill("TERM", pid)
      Process.waitpid(pid)
    rescue Errno::ECHILD, Errno::ESRCH
      nil
    end
    @pipes.each { |pipe| pipe.close unless pipe.closed? }
    Story::Deletion.new(@story).destroy!(confirm: @story.title)
    RubyLLM::ActiveRecord::Model.where.not(id: @models).delete_all
  end

  test "overlapping processes preserve both commands and do not hold SQLite's writer across rendering" do
    red = lying_here(@game, @game.current_location, name: "red coin")
    blue = lying_here(@game, @game.current_location, name: "blue coin")
    stale = Playthrough.find(@game.id)
    stale.current_scene
    entered, signal = pipe
    resume, release = pipe
    attempted, attempting = pipe
    rendered, rendering = pipe

    first = worker do
      agent = FakeAgent.new("You take the red coin.")
      agent.define_singleton_method(:ask) do |*args, **kwargs, &block|
        signal.write("1")
        resume.read(1)
        super(*args, **kwargs, &block)
      end
      BaseAgent.stub(:new, agent) do
        Playthrough::Turn.new(stale).play("/take red coin", request_token: "red")
      end
    end
    assert_equal "1", read(entered)

    second = worker do
      attempting.write("1")
      agent = FakeAgent.new("You take the blue coin.")
      agent.define_singleton_method(:ask) do |*args, **kwargs, &block|
        rendering.write("1")
        super(*args, **kwargs, &block)
      end
      BaseAgent.stub(:new, agent) do
        Playthrough::Turn.new(stale).play("/take blue coin", request_token: "blue")
      end
    end
    assert_equal "1", read(attempted)
    assert_nil IO.select([ rendered ], nil, nil, 0.1), "the second turn cannot render before the first is complete"
    # A separate connection can still write while the first provider waits.
    @story.touch
    release.write("1")
    join(first)
    join(second)

    chain = @game.reload.scene_chain
    assert_equal [ @opening.id, *@story.scenes.where.not(id: @opening.id).order(:id).pluck(:id) ], chain.map(&:id)
    assert_equal [ "take red coin", "take blue coin" ], chain.drop(1).map(&:typed)
    assert_equal [ red.id, blue.id ].sort, @game.carried.pluck(:id).sort
    assert_equal 2, @game.commands.where(status: "completed").count
  end

  test "two processes reaching one loaded stub reuse its first realization" do
    location = create(:location, :stub, story: @story, population: "nobody")
    entered, signal = pipe
    resume, release = pipe
    attempted, attempting = pipe

    first = worker do
      agent = FakeAgent.new({ "description" => "The first room persists.", "lore" => "Old stone." }, { "exits" => [] })
      agent.define_singleton_method(:ask) do |*args, **kwargs, &block|
        unless @waited
          @waited = true
          signal.write("1")
          resume.read(1)
        end
        super(*args, **kwargs, &block)
      end
      BaseAgent.stub(:new, agent) { Location::Generator.new(location).realize! }
    end
    assert_equal "1", read(entered)
    second = worker do
      attempting.write("1")
      BaseAgent.stub(:new, ->(*) { raise "a waiting realizer must reuse the first result" }) do
        Location::Generator.new(location).realize!
      end
    end
    assert_equal "1", read(attempted)
    release.write("1")
    join(first)
    join(second)

    assert_equal "The first room persists.", location.reload.description
    assert_predicate location, :realized?
  end

  test "a killed worker resumes its committed pickup before a later command" do
    coin = lying_here(@game, @game.current_location, name: "red coin")
    entered, signal = pipe
    resume, _release = pipe
    first = worker do
      agent = FakeAgent.new("You take the red coin.")
      original = agent.method(:ask)
      agent.define_singleton_method(:ask) do |*args, **kwargs, &block|
        signal.write("1")
        resume.read(1)
        original.call(*args, **kwargs, &block)
      end
      BaseAgent.stub(:new, agent) do
        Playthrough::Turn.new(Playthrough.find(@game.id)).play("/take red coin", request_token: "killed")
      end
    end
    assert_equal "1", read(entered)
    assert_includes @game.carried, coin
    Process.kill("KILL", first)
    _, status = Timeout.timeout(10) { Process.wait2(first) }
    @children.delete(first)
    assert_equal Signal.list.fetch("KILL"), status.termsig
    assert_equal "running", @game.commands.find_by!(request_token: "killed").status

    # A different game can write while the killed turn was rendering; recovery
    # also has to reacquire the kernel lock, not an expiring application lease.
    started = []
    BaseAgent.stub(:new, FakeAgent.new("You take the red coin.", "You put down the red coin.")) do
      Playthrough::Turn.new(@game.reload).play("/drop red coin", request_token: "later",
                                              on_start: ->(line) { started << line })
    end
    assert_equal [ "/take red coin", "/drop red coin" ], started
    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
    assert_equal %w[take drop], @game.scene_chain.drop(1).map(&:resolved_action)
    assert_equal @game.current_location, coin.reload.location
  end

  test "a worker killed while a character answers leaves one copy of the line in their conversation" do
    keeper = create(:character, story: @story, location: @game.current_location, fullname: "Keeper", nickname: "Keeper")
    entered, signal = pipe
    offline_model!
    first = worker do
      hold_call(signal)
      OfflineExchange.with_model do
        Playthrough::Turn.new(Playthrough.find(@game.id)).play("/talk Keeper", request_token: "killed")
      end
    end
    assert_equal "1", read(entered)
    kill(first)
    conversation = Chat.conversation_with(keeper, @game)
    assert_equal %w[user], conversation.exchange_messages.pluck(:role), "the killed call's prompt was persisted"

    OfflineExchange.with(REACTION, "Keeper nods to you.", LOOK, "You look around.") do
      Playthrough::Turn.new(@game.reload).play("/look", request_token: "later")
    end

    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
    assert_equal %w[user assistant], conversation.exchange_messages.pluck(:role)
    assert_equal 1, Interaction.where(character: keeper).count
  end

  test "a worker killed while a new room's exits are asked resumes with one exits question" do
    quay = create(:location, :stub, story: @story, name: "Quay", population: "nobody")
    create(:location_connection, location: @game.current_location, connected_location: quay, distance: "adjacent")
    entered, signal = pipe
    offline_model!
    first = worker do
      hold_call(signal, after: [ { "description" => "Wet planks and rope.", "lore" => "Boats came here once.", "name" => "Quay" } ])
      OfflineExchange.with_model do
        Playthrough::Turn.new(Playthrough.find(@game.id)).play("/move Quay", request_token: "killed")
      end
    end
    assert_equal "1", read(entered)
    kill(first)
    assert_predicate quay.reload, :stub?
    conversation = Chat.find(quay.generation_checkpoint.fetch("chat_id"))
    assert_equal %w[user assistant user], conversation.exchange_messages.pluck(:role)

    exits = { "exits" => [ { "name" => "Back Lane", "teaser" => "A narrow lane.", "distance" => "adjacent", "travel_method" => "walking" } ] }
    arrival = { "description" => "You reach the quay.", "summary" => "Arrived at the quay." }
    OfflineExchange.with(exits, arrival, LOOK, "You look around.") do
      Playthrough::Turn.new(@game.reload).play("/look", request_token: "later")
    end

    assert_predicate quay.reload, :realized?
    assert_equal quay, @game.reload.current_location
    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
    assert_equal %w[user assistant user assistant], conversation.exchange_messages.pluck(:role)
    assert_equal 1, conversation.messages.where(role: "user").count { |message| message.content.start_with?("Now list the ways out of Quay") }
  end

  private

  REACTION = { "pre_thought" => "A visitor.", "pre_feeling" => "curious", "action" => "I nod.",
               "post_feeling" => "calm", "post_thought" => "Fine.", "inner_resolution" => "I wait.",
               "engine_action" => Playthrough::NpcAction::NONE }.freeze
  LOOK = { "intent" => "other", "target" => "nothing", "also_named" => "nothing", "thrown_at" => "nothing" }.freeze

  # A MODEL CALL THAT NEVER RETURNS, for a worker that is about to be killed.
  # RubyLLM's own `Chat#ask` is `ask_later`, which persists the prompt, and then
  # the request. This keeps the first half and holds where the request would
  # go. The calls listed in `after` are answered offline first.
  def hold_call(signal, after: [])
    answers = after.dup
    Chat.define_method(:ask) do |message = nil, **_options, &block|
      if answers.any?
        add_message(role: :user, content: message)
        next OfflineExchange.persist_answer(self, OfflineExchange.reply(answers.shift), &block)
      end
      ask_later(message)
      signal.write("1")
      sleep
    end
  end

  # THE ONE MODEL ROW THE HELD CALL NEEDS, written by the parent before it forks.
  # A chat saved into an empty registry table loads RubyLLM's whole bundled
  # registry, which is slow enough under a parallel suite to outlast the wait for
  # the signal, and would be committed past this test's teardown.
  def offline_model!
    model = OfflineExchange::MODEL
    RubyLLM::ActiveRecord::Model.find_or_create_by!(model_id: model[:model], provider: model[:provider].to_s) do |row|
      row.name = model[:model]
    end
  end

  def kill(pid)
    Process.kill("KILL", pid)
    _, status = Timeout.timeout(10) { Process.wait2(pid) }
    @children.delete(pid)
    assert_equal Signal.list.fetch("KILL"), status.termsig
    assert_equal "running", @game.commands.find_by!(request_token: "killed").status
  end

  def pipe
    IO.pipe.tap { |ends| @pipes.concat(ends) }
  end

  def read(pipe)
    Timeout.timeout(10) { pipe.read(1) }
  end

  def worker(&block)
    ActiveRecord::Base.connection_handler.clear_all_connections!
    fork do
      begin
        block.call
        exit! 0
      rescue Exception => e # report assertions as well as ordinary failures to the parent
        warn e.full_message
        exit! 1
      end
    end.tap { |pid| @children << pid }
  end

  def join(pid)
    _child, status = Timeout.timeout(15) { Process.wait2(pid) }
    @children.delete(pid)
    assert_predicate status, :success?, "worker #{pid} failed"
  end
end
