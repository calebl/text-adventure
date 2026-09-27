# THE SWITCH TO THE RUST ENGINE, and everything Ruby knows about it.
#
# The Rust engine (https://github.com/renderedstep/engine) plays the same game
# over the same SQLite schema: the same rules, the same dice, the same journal,
# the same model requests. With `TA_ENGINE=rust`, `Playthrough::Session#play`
# hands it each whole turn through a native extension (`ext/renderedstep`),
# so every front end -- the browser, the API, anything else that plays
# through the session -- plays on Rust, while Turbo, the labs, the benches,
# the doctor, repair, seeding and every backfill stay Ruby on the same
# database. README.md ("The Rust engine") says how to build it.
#
# RUBY IS THE DEFAULT AND THE FALLBACK. Without the variable nothing here runs.
# With it, a turn still plays on Ruby -- logged and counted, see `.fell_back!`
# -- whenever Rust cannot take it:
#
# - the extension is not built, or does not load;
# - the turn has no request token (every front end's has one; the journal and
#   the queue are keyed on it);
# - `TA_LOCAL_MODELS` is set, because the local rotation exists only in Ruby
#   and a turn that asked a different set of models would be a different game;
# - Ruby holds a transaction open, because SQLite has one writer and the Rust
#   engine writes on its own connection: it would wait on this process and see
#   none of its uncommitted rows (a whole turn, never a rule inside one);
# - the engine answers with an ENGINE error -- a schema it is not written
#   against, a rule it does not play yet, a database failure, a panic it
#   caught. `Playthrough::RustEngine::Turn` hands the turn back first, so the
#   Ruby engine finishes it from the same journal a stopped worker leaves.
#
# A MODEL FAILURE IS NOT AN ENGINE ERROR. The engine has already asked every
# model in the rotation by the time one comes back, so asking Ruby to try again
# would pay for the same turn twice. It is raised as the Ruby engine's own
# exception (`.exception_for`), and the player is told what the Ruby engine
# would have told them.
#
# THE CREDENTIALS ARE THE ONES RUBY USES. `.models` reads `OPENROUTER_API_KEY`
# (the Direct route), `OPENROUTER_MODEL`, and the System One keys exactly as
# `BaseAgent` and `SystemOneAgent` do, and hands them over as one document.
# Nothing here logs that document, and the engine keeps a key as a value that
# cannot be printed.
module Playthrough::RustEngine
  VARIABLE = "TA_ENGINE".freeze

  # Where `bin/rails engine:build` leaves the extension; `require` adds the
  # platform's own suffix.
  EXTENSION = Rails.root.join("ext/renderedstep/build/renderedstep_native").to_s

  # The engine's error kinds that hand a turn back to the Ruby engine. Every
  # other kind is how the turn ended, and is raised.
  HANDED_BACK = %w[schema_mismatch schema_changed no_such_playthrough no_such_story database unsupported panicked].freeze

  # A model call failed after the rotation was exhausted, in a way the Ruby
  # engine has no exception class of its own for.
  class ModelFailed < StandardError; end

  # A replayed provider a sweep step declared unavailable.
  class ProviderUnavailable < ModelFailed; end

  # A replayed call nobody declared, or one out of order.
  class ReplayMismatch < ModelFailed; end

  # The turn was stopped after a named journal step, as a killed worker stops.
  # An `Interrupt`, as the sweep's own stopped worker is, so nothing that
  # rescues a StandardError mistakes it for a failed turn.
  class Stopped < Interrupt; end

  FALLBACKS = Concurrent::Map.new

  def self.wanted?
    forced = Thread.current[:rust_engine]
    return forced == :rust unless forced.nil?

    ENV[VARIABLE].to_s.strip.casecmp?("rust")
  end

  # Plays the block with the switch set one way for this thread, whatever the
  # environment says: the parity gates play a Rust walk and its Ruby twin in
  # one process.
  def self.using(engine)
    raise ArgumentError, "an engine is :rust or :ruby" unless %i[rust ruby].include?(engine)

    previous = Thread.current[:rust_engine]
    Thread.current[:rust_engine] = engine
    yield
  ensure
    Thread.current[:rust_engine] = previous
  end

  # The extension's module, or nil when it is not built or does not load --
  # asked once per process, and the reason kept for the log.
  def self.extension
    return @extension if defined?(@extension)

    @extension = begin
      require EXTENSION
      ::RenderedStep
    rescue LoadError, StandardError => e
      @load_error = "#{e.class}: #{e.message}"
      nil
    end
  end

  def self.load_error = extension ? nil : @load_error

  # WHY THIS TURN CANNOT BE HANDED OVER, or nil when it can. Asked before the
  # game's lock is taken, so a turn that plays on Ruby waits once.
  def self.unplayable(request_token)
    return :no_request_token if request_token.blank?
    return :not_built if extension.nil?
    return :local_models if ENV["TA_LOCAL_MODELS"].present?
    return :transaction_open if ActiveRecord::Base.connection.transaction_open?

    nil
  end

  # A turn that plays on Ruby although Rust was asked for: said in the log, and
  # counted in this process (`.fallbacks`) and to anybody subscribed to
  # `fallback.rust_engine`.
  def self.fell_back!(reason, detail = nil)
    FALLBACKS.compute(reason.to_s) { |count| count.to_i + 1 }
    ActiveSupport::Notifications.instrument("fallback.rust_engine", reason: reason.to_s, detail: detail)
    Rails.logger.warn { "Rust engine: this turn plays on Ruby (#{[ reason, detail ].compact.join(": ")})" }
  end

  # How many turns fell back in this process, by reason.
  def self.fallbacks = FALLBACKS.each_pair.to_h

  def self.database = File.expand_path(ApplicationRecord.connection_db_config.database, Rails.root)

  # One submitted line, played by the engine on its own connection. Answers
  # the engine's document, parsed; the block receives prose as it streams.
  def self.submit(playthrough, line, request_token, &block)
    document = replay_document || models
    answer = extension.submit(database, playthrough.id, line, request_token, document.to_json, &block)
    JSON.parse(answer).tap { |parsed| replayed!(parsed["replay"]) if parsed.key?("replay") }
  ensure
    # The engine wrote on another connection: nothing this one cached is true.
    ActiveRecord::Base.connection.clear_query_cache
  end

  # One line played with no model at all, in one transaction, with `decision`
  # standing in for what a person answers when it is a conversation. The
  # engine sweep's typed steps; no front end plays this way.
  def self.play(playthrough, line, decision: nil)
    JSON.parse(extension.play(database, playthrough.id, line, decision))
  ensure
    ActiveRecord::Base.connection.clear_query_cache
  end

  # WHERE THE ENGINE'S MODEL CALLS GO, read off the environment exactly as the
  # Ruby engine reads it: the player's OpenRouter key as the Direct route
  # (`BaseAgent`), `OPENROUTER_MODEL` asked first, and System One on TypeSafe
  # when its key is set and on OpenRouter's decisions route otherwise
  # (`SystemOneAgent.transport`). Holds the keys: never log it.
  def self.models
    live_models_guard&.call
    key = ENV[SystemOneAgent::OPENROUTER_API_KEY_VARIABLE].presence
    typesafe = ENV[SystemOneAgent::TYPESAFE_API_KEY_VARIABLE].presence
    {
      route: key ? "direct" : "none", key: key, model: ENV["OPENROUTER_MODEL"].presence,
      system_one: if typesafe then "typesafe" elsif key then "decisions" else "off" end,
      typesafe_key: typesafe
    }
  end

  # Called before a live models document is built; the engine sweep sets it to
  # fail the walk, as it fails one that reaches `BaseAgent.new`.
  mattr_accessor :live_models_guard

  # THE SWEEP'S PROVIDERS, for a browser step that plays on Rust: each call is
  # answered with the next of `replies` (the step's own), and `stop_after`
  # stops the turn after that journal step. The engine's answer to what was
  # asked is read back with `.replayed` once the block has run.
  def self.replaying(replies, stop_after: nil)
    previous = Thread.current[:rust_engine_replay]
    Thread.current[:rust_engine_replay] = { replay: replies, stop_after: stop_after }.compact
    Thread.current[:rust_engine_replayed] = nil
    yield
  ensure
    Thread.current[:rust_engine_replay] = previous
  end

  # The calls the engine made of a replay, and why it did not finish cleanly
  # (`unfinished`, nil when every declared reply was asked for in order and
  # every prompt said what it had to) -- or nil when no turn played on Rust.
  def self.replayed = Thread.current[:rust_engine_replayed]

  def self.replay_document = Thread.current[:rust_engine_replay]
  def self.replayed!(value) = Thread.current[:rust_engine_replayed] = value
  private_class_method :replay_document, :replayed!

  # THE RUBY ENGINE'S OWN EXCEPTION for how an engine turn ended, so
  # `Playthrough::Session.ending_for` tells the player exactly what it tells
  # them about a Ruby turn: the crisis notice, the setup notice, the failure
  # copy. The engine's message never carries a request or a key.
  def self.exception_for(error)
    message = error.fetch("message")
    case [ error.fetch("kind"), error["failure"] ]
    in [ "interrupted", _ ] then Playthrough::Command::InterruptedError.new(message)
    in [ "previously_failed", _ ] then Playthrough::Command::PreviouslyFailedError.new(message)
    in [ "stopped", _ ] then Stopped.new(message)
    in [ "model", "crisis" ] then BaseAgent::CrisisResponseError.new(message)
    in [ "model", "no_model" ] then BaseAgent::NoModelConfiguredError.new(message)
    in [ "model", "unauthorized" ] then BaseAgent::UnauthorizedProviderError.new(message)
    in [ "model", "refused" ] then BaseAgent::RefusalError.new(message)
    in [ "model", "schema_ignored" ] then BaseAgent::SchemaIgnoredError.new(message)
    in [ "model", "unavailable" ] then ProviderUnavailable.new(message)
    in [ "model", "unexpected" ] then ReplayMismatch.new(message)
    else ModelFailed.new(message)
    end
  end
end
