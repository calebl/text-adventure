require "test_helper"
require "rake"

class PlayersTasksTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("players:invite")
    %w[players:invite players:revoke players:limit].each { |name| Rake::Task[name].reenable }
  end

  def run_task(name, *args)
    out, = capture_io { Rake::Task[name].invoke(*args) }
    out
  end

  test "invite prints a token once that authenticates, and stores only its digest" do
    out = run_task("players:invite", "Ada")
    token = out.lines.map(&:strip).reject(&:empty?).last

    player = Player.find_by!(name: "Ada")
    assert_equal player, Player.authenticate(token)
    assert_equal Player.digest(token), player.token_digest
    assert_equal Player::DEFAULT_MONTHLY_LIMIT_USD, player.monthly_limit_usd
  end

  test "revoke stops the token and keeps the player" do
    token = run_task("players:invite", "Ada").lines.map(&:strip).reject(&:empty?).last
    run_task("players:revoke", "Ada")
    assert_nil Player.authenticate(token)
    assert Player.exists?(name: "Ada")
  end

  test "limit sets the monthly limit and refuses a nonsense amount" do
    create(:player, name: "Ada")
    run_task("players:limit", "Ada", "2.50")
    assert_equal BigDecimal("2.5"), Player.find_by!(name: "Ada").monthly_limit_usd

    Rake::Task["players:limit"].reenable
    assert_raises(SystemExit) { capture_io { Rake::Task["players:limit"].invoke("Ada", "lots") } }
  end
end
