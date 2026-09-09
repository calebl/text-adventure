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

  private

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
