# THE HOSTED MODE'S OUTER DOOR: a request for anything but the engine API, the
# model relay's two routes (`Relay`) or the health check is answered 404 before
# it reaches a router.
#
# config/routes.rb already draws nothing else when `config.x.hosted_api_only`
# is on, and this is the second lock, because the app's own routes are not the
# only ones: the frameworks `rails/all` loads (Active Storage, Action Mailbox
# and its conductor, Turbo's history routes) append routes of their own that
# no route file controls. None of them is used by the API, so none of them is
# served. What passes is decided by the path alone, so it cannot depend on how
# any of those frameworks happens to be configured.
class HostedApiOnly
  ALLOWED = %r{\A/(api/v1(/|\z|\.json\z)|relay/openrouter/api/(v1/chat/completions|alpha/decisions)\z|up\z)}

  NOT_FOUND = [ 404, { "content-type" => "application/json" },
                [ { error: { code: "not_found", message: "There is nothing here by that id." } }.to_json ] ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) if env["PATH_INFO"].to_s.match?(ALLOWED)

    NOT_FOUND.dup.tap { |response| response[2] = response[2].dup }
  end
end
