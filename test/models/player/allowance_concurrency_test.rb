require "test_helper"
require "timeout"

# THE CAP CANNOT BE CROSSED BY RACING IT. Real processes, committed rows and
# the real locks: every worker is released at once to accept a line into the
# same player's games, and exactly as many are admitted as the headroom holds.
# Transactional fixtures would hide the rows from the workers, so this test
# commits them and cleans up after itself, like `Playthrough::TurnConcurrencyTest`.
class Player::AllowanceConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  WORKERS = 8
  ACCEPTED = 0
  REFUSED = 3

  setup do
    # 0.02 spent against 0.10: room for exactly two reservations of 0.03.
    @player = create(:player, monthly_limit_usd: BigDecimal("0.10"))
    @games = Array.new(2) { create(:playthrough, :started, player: @player) }
    create(:system_one_receipt, player: @player, cost_usd: BigDecimal("0.02"))
    @children = []
  end

  teardown do
    @children.each do |pid|
      Process.kill("TERM", pid)
      Process.waitpid(pid)
    rescue Errno::ECHILD, Errno::ESRCH
      nil
    end
    stories = @games.map(&:story)
    SystemOneReceipt.where(player: @player).delete_all
    RelayReceipt.where(player: @player).delete_all
    stories.each { |story| Story::Deletion.new(story).destroy!(confirm: story.title) }
    @player.reload.destroy!
  end

  test "racing workers are admitted exactly as many turns as the limit holds" do
    go, start = IO.pipe
    ActiveRecord::Base.connection_handler.clear_all_connections!
    WORKERS.times do |index|
      @children << fork do
        go.read(1)
        game = Playthrough.find(@games[index % 2].id)
        Playthrough::Session.new(game).accept!("/look", "race-#{index}")
        exit! ACCEPTED
      rescue Player::Allowance::LimitReached
        exit! REFUSED
      rescue Exception => e # rubocop:disable Lint/RescueException
        warn e.full_message
        exit! 1
      end
    end
    start.write("1" * WORKERS)
    start.close

    statuses = @children.map { |pid| Timeout.timeout(20) { Process.wait2(pid).last.exitstatus } }
    @children.clear

    assert_equal [ ACCEPTED, ACCEPTED, *Array.new(WORKERS - 2, REFUSED) ], statuses.sort
    assert_equal 2, Playthrough::Command.where(playthrough: @games).count
    assert_operator @player.allowance.spent + @player.allowance.reserved, :<=, @player.monthly_limit_usd
  ensure
    go&.close
  end

  # The relay's gate is the same one: a call is admitted by opening its
  # receipt inside `admit!`, and the receipt's hold is what the next racer
  # counts. 0.02 spent against 0.10 leaves room for exactly two calls of 0.04.
  test "racing relay calls are admitted exactly as many as the limit holds" do
    request = Struct.new(:route, :model, :reservation) { def stream? = false }
                    .new(:chat_completions, BaseAgent::REMOTE_MODEL_IDS.first, BigDecimal("0.04"))
    go, start = IO.pipe
    ActiveRecord::Base.connection_handler.clear_all_connections!
    WORKERS.times do
      @children << fork do
        go.read(1)
        player = Player.find(@player.id)
        player.allowance.admit!(request.reservation, held_for: "the call") { RelayReceipt.open!(player, request) }
        exit! ACCEPTED
      rescue Player::Allowance::LimitReached
        exit! REFUSED
      rescue Exception => e # rubocop:disable Lint/RescueException
        warn e.full_message
        exit! 1
      end
    end
    start.write("1" * WORKERS)
    start.close

    statuses = @children.map { |pid| Timeout.timeout(20) { Process.wait2(pid).last.exitstatus } }
    @children.clear

    assert_equal [ ACCEPTED, ACCEPTED, *Array.new(WORKERS - 2, REFUSED) ], statuses.sort
    assert_equal 2, RelayReceipt.where(player: @player).unsettled.count
    assert_operator @player.allowance.spent + @player.allowance.reserved, :<=, @player.monthly_limit_usd
  ensure
    go&.close
  end
end
