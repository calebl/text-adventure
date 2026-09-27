require "test_helper"
require "open3"
require Rails.root.join("lib/middleware/hosted_api_only")

# THE HOSTED MODE SERVES THE API, THE MODEL RELAY AND /up, AND NOTHING ELSE. Two locks, and
# both are checked: the routes a hosted boot draws, and the middleware that
# answers 404 for every other path -- including the routes frameworks append
# that no route file controls.
class HostedApiOnlyTest < ActiveSupport::TestCase
  BROWSER_PATHS = [
    "/", "/playthroughs", "/playthroughs/1", "/playthroughs/1/turns", "/playthroughs/1/debug",
    "/playthroughs/1/machinery/1", "/playthroughs/1/map", "/playthroughs/1/feedbacks",
    "/stories/1/map", "/lab/kinds", "/lab/exits", "/lab/exits/vantages", "/cable",
    "/rails/active_storage/direct_uploads", "/rails/conductor/action_mailbox/inbound_emails",
    "/recede_historical_location", "/assets/application.css", "/up/../playthroughs", "/api/v10",
    "/relay", "/relay/openrouter", "/relay/openrouter/api/v1/models", "/relay/openrouter/api/v1/chat/completions/x",
    "/relay/openrouter/api/v1/chat/completions.json", "/relay/openrouter/api/alpha/decisions/../../v1/keys"
  ].freeze

  RELAY_PATHS = %w[/relay/openrouter/api/v1/chat/completions /relay/openrouter/api/alpha/decisions].freeze

  OK = [ 200, {}, [ "passed" ] ].freeze

  test "the middleware passes the API, the relay's two routes and the health check and refuses everything else" do
    gate = HostedApiOnly.new(->(_env) { OK })

    [ *%w[/up /api/v1 /api/v1/ /api/v1/worlds /api/v1/games/abc/turns/1/events], *RELAY_PATHS ].each do |path|
      assert_equal 200, gate.call("PATH_INFO" => path).first, path
    end
    BROWSER_PATHS.each { |path| assert_equal 404, gate.call("PATH_INFO" => path).first, path }
  end

  # A real boot with the switch on, in its own process, so nothing about this
  # test process's routes or middleware is changed. It reads only.
  test "a hosted boot draws only the API, the relay and /up, stacks the gate first, and mounts no cable" do
    script = <<~RUBY
      paths = Rails.application.routes.routes.map { |r| r.path.spec.to_s }
      app = paths.reject { |p| p.start_with?("/rails/", "/recede_", "/refresh_", "/resume_") }
      client = Rack::MockRequest.new(Rails.application)
      reached = #{RELAY_PATHS.inspect}.to_h { |path| [ path, client.post(path).status ] }
      puts JSON.generate(app: app.uniq, first: Rails.application.middleware.first.klass.to_s,
                         cable: Rails.application.config.action_cable.mount_path, reached: reached)
    RUBY
    out, err, status = Open3.capture3({ "TA_HOSTED_API_ONLY" => "1", "RAILS_ENV" => "test" },
                                      "bin/rails", "runner", script, chdir: Rails.root.to_s)
    assert_predicate status, :success?, err
    booted = JSON.parse(out.lines.last)

    assert_equal "HostedApiOnly", booted["first"]
    assert_nil booted["cable"]
    assert booted["app"].all? { |path| path.start_with?("/api/v1", "/up") || RELAY_PATHS.include?(path) }, booted["app"].inspect
    assert_includes booted["app"], "/api/v1(.:format)"
    assert_includes booted["app"], "/up(.:format)"
    RELAY_PATHS.each { |path| assert_includes booted["app"], path }
    # Through the whole hosted stack to the relay's own door, which asks for a token.
    assert_equal RELAY_PATHS.to_h { |path| [ path, 401 ] }, booted["reached"]
  end

  test "an ordinary boot keeps the browser and does not stack the gate" do
    assert_not Rails.configuration.x.hosted_api_only
    assert_not_includes Rails.application.middleware.map(&:klass), HostedApiOnly
  end
end
