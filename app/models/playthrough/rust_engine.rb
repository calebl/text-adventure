# THE RUST ENGINE, AND EVERYTHING RUBY KNOWS ABOUT IT.
#
# The Rust engine (https://github.com/renderedstep/engine) plays the game:
# `Playthrough::Session#play` hands it every whole turn through a native
# extension (`ext/renderedstep`), so every front end -- the browser, the API,
# anything else that plays through the session -- plays on Rust. Turbo, the
# labs, the benches, the doctor, repair, seeding and every backfill stay Ruby,
# on the same database. README.md ("The Rust engine") says how to build it; a
# checkout cannot play without it.
#
# THERE IS NO FALLBACK. A turn the engine cannot play fails, in the engine's
# own words, and is never played again on Ruby behind the player's back:
# `EngineError` carries the words, `Playthrough::Session.ending_for` shows them
# as the turn's failure notice, and `.failed!` logs and counts it. That covers
# an extension that is not built or does not load, a database transaction left
# open around the call (SQLite has one writer, and the engine writes on its own
# connection), and every error the engine answers with: a schema it is not
# written against, a rule it does not play yet, a database failure, a panic it
# caught.
#
# A MODEL FAILURE IS HOW A TURN ENDED, not an engine error. It is raised as the
# Ruby app's own exception for it (`.exception_for`), so the player is told what
# they have always been told: the crisis notice, the setup notice, the failure
# copy.
#
# THE RUBY TURN LOOP IS THE PARITY REFERENCE, and nothing else. `Playthrough::Turn`
# stays in the code because the parity gates judge the Rust engine against what
# it does (`bin/rails engine:rust_gates`), and the engine sweep and the suite's
# transactional tests exercise it. `.using(:ruby)` plays it for one block;
# `.reference_by_default!` makes it the default for the test suite and refuses
# anywhere else. No setting turns it on for a player.
#
# THE CREDENTIALS ARE THE ONES RUBY USES. `.models` reads `OPENROUTER_API_KEY`
# (the Direct route), `OPENROUTER_MODEL`, and the System One keys exactly as
# `BaseAgent` and `SystemOneAgent` do, and hands them over as one document.
# Nothing here logs that document, and the engine keeps a key as a value that
# cannot be printed. The local rotation (`TA_LOCAL_MODELS`) is Ruby's alone, so
# it never reaches a turn.
module Playthrough::RustEngine
  # Where `bin/rails engine:build` leaves the extension; `require` adds the
  # platform's own suffix.
  EXTENSION = Rails.root.join("ext/renderedstep/build/renderedstep_native").to_s

  ENGINES = %i[rust ruby].freeze

  # A turn the engine could not play, in its own words. `kind` is the engine's
  # name for the error (`unsupported`, `database`, ...), or `not_built` and
  # `transaction_open` for the two this side finds before asking it.
  class EngineError < StandardError
    attr_reader :kind

    def initialize(kind, message)
      @kind = kind.to_s
      super(message)
    end

    # What the player reads.
    def notice = "The engine could not play that turn: #{message}"
  end

  # A model call failed after the rotation was exhausted, in a way the Ruby
  # app has no exception class of its own for.
  class ModelFailed < StandardError; end

  # A replayed provider a sweep step declared unavailable.
  class ProviderUnavailable < ModelFailed; end

  # A replayed call nobody declared, or one out of order.
  class ReplayMismatch < ModelFailed; end

  # The turn was stopped after a named journal step, as a killed worker stops.
  # An `Interrupt`, as the sweep's own stopped worker is, so nothing that
  # rescues a StandardError mistakes it for a failed turn.
  class Stopped < Interrupt; end

  FAILURES = Concurrent::Map.new

  # Which engine plays a turn: Rust, unless this thread is playing the Ruby
  # reference, or the test suite made it the default.
  def self.engine = Thread.current[:turn_engine] || @default || :rust

  # Plays the block on one engine, for this thread: the parity gates play a
  # Rust walk and its Ruby twin in one process, and the switch's own tests play
  # Rust inside a suite whose default is the reference.
  def self.using(engine)
    raise ArgumentError, "an engine is one of #{ENGINES.inspect}" unless ENGINES.include?(engine)

    previous = Thread.current[:turn_engine]
    Thread.current[:turn_engine] = engine
    yield
  ensure
    Thread.current[:turn_engine] = previous
  end

  # THE SUITE'S DEFAULT. Almost every test plays inside a transaction the
  # engine could neither see into nor write past, so the suite plays the Ruby
  # reference unless a test asks for Rust. Refused outside the test
  # environment: there is no way to turn the reference on for a player.
  def self.reference_by_default!
    raise EngineError.new(:reference, "the Ruby turn loop is the parity reference, not a way to play") unless Rails.env.test?

    @default = :ruby
  end

  # The extension's module, or nil when it is not built or does not load --
  # asked once per process, and the reason kept.
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

  # WHY THIS PROCESS CANNOT HAND THE ENGINE A TURN RIGHT NOW, as the error the
  # turn fails with, or nil when it can.
  def self.unplayable
    if extension.nil?
      return EngineError.new(:not_built, "the Rust engine's extension is not built or did not load " \
                                         "(#{load_error}); run bin/rails engine:build")
    end
    if ActiveRecord::Base.connection.transaction_open?
      return EngineError.new(:transaction_open, "a database transaction is open around the turn, and the engine " \
                                                "writes on a connection of its own")
    end

    nil
  end

  # A turn the engine could not play: said in the log, and counted in this
  # process (`.failures`) and to anybody subscribed to `failure.rust_engine`.
  def self.failed!(error)
    FAILURES.compute(error.kind) { |count| count.to_i + 1 }
    ActiveSupport::Notifications.instrument("failure.rust_engine", kind: error.kind, message: error.message)
    Rails.logger.error { "Rust engine: a turn failed (#{error.kind}): #{error.message}" }
  end

  # How many turns the engine could not play in this process, by kind.
  def self.failures = FAILURES.each_pair.to_h

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
  # Ruby app reads it: the player's OpenRouter key as the Direct route
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

  # THE EXCEPTION an engine turn ended in. A model failure is the Ruby app's
  # own exception for it, so `Playthrough::Session.ending_for` tells the player
  # exactly what it has always told them; anything else the engine answers is
  # an `EngineError` in its words. The engine's message never carries a
  # request or a key.
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
    in [ "model", _ ] then ModelFailed.new(message)
    in [ kind, _ ] then EngineError.new(kind, message)
    end
  end
end
