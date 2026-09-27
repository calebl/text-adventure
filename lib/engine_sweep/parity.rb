# THE SAME SCRIPT PLAYED THROUGH TWO ENGINES, compared step by step.
#
# A sweep script says what should happen; `EngineSweep::Dump` says what did,
# whole. This plays a script through an ENGINE -- anything that answers
# `#play(script)` with one dump per step, in the script's order -- and either
# writes the dumps down as golden files or compares two engines' and names the
# first step where they part. docs/engine-parity.md is the contract an engine
# implements.
#
# THE GOLDENS ARE THE RUST ENGINE'S. Its parity binary writes them and this
# repository vendors them at the pinned commit (`EngineSweep::Vendored`), so
# `bin/rails engine:parity`, which writes them from the Rust walk here, is for
# writing them into a checkout of the engine, never for moving them here on
# their own.
#
# `InProcess` plays a script on the engine this app plays, through its
# extension. `Command` is an engine behind a subprocess: it is handed a
# script's path and prints one dump per line. `Ruby` is the Ruby reference
# loop, `EngineSweep::Walk` with a listener, which wrote the goldens until the
# engine took them over; no gate plays it, and it stays for asking by hand
# where the two loops part (`Parity.diff(Parity::Ruby.new, first: ...)`).
#
# NO MODEL, ON EITHER SIDE. The Ruby engine plays inside
# `EngineSweep.without_a_model`, and a subprocess is started with both
# provider keys removed from its environment, so a shell that has them still
# plays the keyless game.
module EngineSweep::Parity
  # The golden files: one per script, named after it.
  DIRECTORY = "test/engine_parity".freeze

  # The keys a subprocess engine is never handed. A key in the environment is a
  # switch in this app (`SystemOneAgent.configured?`), not merely a credential.
  WITHHELD = %w[OPENROUTER_API_KEY TYPESAFE_API_KEY].freeze

  class Ruby
    def name = "ruby"

    def play(script)
      dumps = []
      EngineSweep.without_a_model do
        EngineSweep::Walk.new(script, on_step: ->(_step, dump) { dumps << JSON.parse(dump.to_h.to_json) }).play
      end
      dumps
    end
  end

  class Command
    attr_reader :name

    # `shared_database` turns on the second contract in docs/engine-parity.md,
    # where this side owns the database and the engine plays one step per call
    # (`ENGINE_DATABASE`). `launch` is how a command is run, `Open3.capture2`'s
    # signature; a test hands in an engine that runs in-process.
    def initialize(command, shared_database: false, launch: Open3.method(:capture2))
      @command = command
      @name = command
      @shared_database = shared_database
      @launch = launch
    end

    def play(script)
      @shared_database ? play_shared(script) : play_whole(script)
    end

    private

    def environment = WITHHELD.to_h { |key| [ key, nil ] }

    def play_whole(script)
      output, status = @launch.call(environment, *Shellwords.split(@command), script.path.to_s)
      raise EngineSweep::InvalidScript, "#{@command} failed on #{script.name} (#{status})" unless status.success?

      output.lines.map(&:strip).reject(&:empty?).map { |line| JSON.parse(line) }
    end

    # THIS SIDE PREPARES THE WORLD, PLAYS THE RE-SEEDS AND RENDERS THE NOTICES;
    # the engine plays every typed step, one call each, on the same file. The
    # file is a scratch copy of this database, in a directory that is deleted
    # when the script is done, so neither side can write the database it came
    # from.
    def play_shared(script)
      Dir.mktmpdir("engine-parity") do |directory|
        file = File.join(directory, "#{script.name}.sqlite3")
        EngineSweep::Parity.copy_database!(file)
        walk = EngineSweep::Walk.new(script)
        on_file(file) { walk.prepare! }

        script.steps.map do |step|
          next on_file(file) { JSON.parse(walk.reseed_step(step).to_h.to_json) } if step.reseed?

          dump = play_one(script, step, file)
          if step.browser && step.expectation.document.key?("shown")
            dump["shown"] = on_file(file) { EngineSweep::BrowserTurn.visible_notices(walk.game_of(step.player)) }
          end
          dump
        end
      end
    end

    def play_one(script, step, file)
      output, status = @launch.call(environment.merge("ENGINE_STEP" => step.index.to_s), *Shellwords.split(@command),
                                    "--database", file, "--player", step.player, script.path.to_s)
      raise EngineSweep::InvalidScript, "#{@command} failed on #{script.name} #{step.label} (#{status})" unless status.success?

      lines = output.lines.map(&:strip).reject(&:empty?)
      raise EngineSweep::InvalidScript, "#{@command} printed #{lines.size} dump(s) for #{script.name} #{step.label}" unless lines.size == 1

      JSON.parse(lines.first)
    end

    def on_file(file, &) = EngineSweep::Parity.on_database(file) { EngineSweep.without_a_model(&) }
  end

  # THE SHARED-DATABASE MODE, IN THIS PROCESS. The runner's half is exactly
  # `Command`'s -- a scratch copy of this database, the world prepared on it
  # and committed, every `reseed:` step played here -- and every typed step is
  # `EngineSweep::Walk#play_step` on that file, with nothing held open between
  # steps. `engine` says which engine plays them: `:ruby`, or `:rust`, which is
  # the Rust engine through its extension -- the typed steps through
  # `EngineSweep::RustMechanics`, the browser steps through
  # `Playthrough::Session`. So a Rust walk plays through the same seam the
  # front ends do, and a turn the engine could not play fails the step with
  # the engine's own error.
  class InProcess
    attr_reader :engine

    def initialize(engine)
      @engine = engine
    end

    def name = "#{engine} (in process)"

    def play(script) = Dir.mktmpdir("engine-parity") { |directory| play_in(directory, script).dumps }

    # THE SWEEP ON THIS ENGINE: the walk played as `#play_in` plays it, with
    # every step's expectation checked as it is played and the invariants
    # checked over the file afterwards, as an `EngineSweep::Result`. A step the
    # engine could not play ends the walk there, as a failure of the script.
    def sweep(script)
      Dir.mktmpdir("engine-sweep") do |directory|
        played = play_in(directory, script)
        broken = on_file(played.file) do
          story = Story.find_by!(title: "#{script.story}#{EngineSweep::Walk::TITLE_SUFFIX}")
          EngineSweep::Invariants.new(story, seed: played.walk.loaded).check.map { |row| row.with(script: script) }
        end
        EngineSweep::Result.new(script: script, steps: script.steps.size, failures: played.walk.unmet + broken)
      end
    rescue EngineSweep::RustMechanics::Failed, Playthrough::RustEngine::EngineError => e
      stopped = EngineSweep::Result::Broken.new(script: script, invariant: "every_step_played", detail: e.message)
      EngineSweep::Result.new(script: script, steps: script.steps.size, failures: [ stopped ])
    end

    Played = Data.define(:dumps, :file, :walk)

    # Plays `script` on a scratch copy in `directory`, and keeps the file for
    # whoever wants to read what the engine wrote there.
    def play_in(directory, script)
      file = File.join(directory, "#{script.name}.#{engine}.sqlite3")
      EngineSweep::Parity.copy_database!(file)
      walk = EngineSweep::Walk.new(script, engine: engine)
      on_file(file) { walk.prepare! }
      dumps = script.steps.map do |step|
        on_file(file) { step.reseed? ? walk.reseed_step(step) : walk.play_step(step) }
          .then { |dump| JSON.parse(dump.to_h.to_json) }
      end
      Played.new(dumps: dumps, file: file, walk: walk)
    end

    def on_file(file, &block)
      EngineSweep::Parity.on_database(file) do
        EngineSweep.without_a_model { Playthrough::RustEngine.using(engine, &block) }
      end
    end
  end

  # A copy of the database this process is connected to, written to `file` with
  # SQLite's backup: every table, row and counter as last committed. Refuses to
  # write over the database itself.
  def self.copy_database!(file)
    source = ActiveRecord::Base.connection_db_config.database
    raise EngineSweep::InvalidScript, "no database file to copy (#{source.inspect})" unless source && File.file?(source)
    raise EngineSweep::InvalidScript, "#{file} is the database itself" if File.expand_path(file) == File.expand_path(source)

    from = SQLite3::Database.new(source, readonly: true)
    to = SQLite3::Database.new(file)
    backup = SQLite3::Backup.new(to, "main", from, "main")
    backup.step(-1)
    backup.finish
  ensure
    to&.close
    from&.close
  end

  # The name a scratch copy's connection goes by. The suite exempts it from
  # its transaction (`skip_transactional_tests_for_database`, in
  # test/test_helper.rb): a step has to commit on the copy for the engine, on
  # a connection of its own, to read it.
  SCRATCH = "engine_scratch".freeze

  # Runs the block with every model connected to `file` instead, and puts the
  # connection back afterwards. A handler of its own, so a transaction open on
  # the usual connection -- the suite's, say -- is left exactly as it was.
  def self.on_database(file)
    original = ActiveRecord::Base.connection_handler
    handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
    ActiveRecord::Base.connection_handler = handler
    ActiveRecord::Base.establish_connection(
      ActiveRecord::DatabaseConfigurations::HashConfig.new(Rails.env, SCRATCH, { adapter: "sqlite3", database: file.to_s })
    )
    yield
  ensure
    handler&.clear_all_connections!
    ActiveRecord::Base.connection_handler = original if original
  end

  # One engine's play of one script, as the golden file holds it: each step's
  # label, player and typed line beside its dump, so a file can be read
  # without the script open beside it.
  def self.document(script, dumps)
    unless dumps.size == script.steps.size
      raise EngineSweep::InvalidScript, "#{script.name}: #{script.steps.size} step(s) but #{dumps.size} dump(s)"
    end

    steps = script.steps.zip(dumps).map do |step, dump|
      { "step" => step.label, "player" => step.player, "typed" => step.typed, "dump" => dump }
    end
    { "script" => script.name, "story" => script.story, "steps" => steps }
  end

  def self.render(document) = "#{JSON.pretty_generate(document)}\n"

  # Every script's golden file, as { file name => body }, played by `engine`.
  def self.files(engine, scripts = EngineSweep.scripts)
    scripts.to_h { |script| [ "#{script.name}.json", render(document(script, engine.play(script))) ] }
  end

  # Writes them into `directory`: this repository's goldens by default, or a
  # checkout of the engine's (`parity/goldens`).
  def self.write!(engine, scripts = EngineSweep.scripts, directory: DIRECTORY)
    directory = Rails.root.join(directory)
    FileUtils.mkdir_p(directory)
    files(engine, scripts).each { |name, body| directory.join(name).write(body) }
  end

  # The first step at which two lists of dumps disagree, as a sentence, or nil
  # when they agree throughout. Keys are compared in dump order so the first
  # divergence named is the first key a reader would look at.
  def self.first_divergence(script, expected, actual)
    script.steps.each_with_index do |step, index|
      want = expected[index]
      got = actual[index]
      return "#{script.name}: #{step.label} typed #{step.typed.inspect} -- the second engine has no dump" if got.nil?

      key = EngineSweep::Dump::KEYS.find { |candidate| want[candidate] != got[candidate] }
      next if key.nil?

      return "#{script.name}: #{step.label} typed #{step.typed.inspect}\n  " \
             "#{key}: #{want[key].to_json}\n  #{" " * key.size}  #{got[key].to_json} (second engine)"
    end
    return nil if actual.size <= expected.size

    "#{script.name}: the second engine answered #{actual.size} step(s) for #{expected.size}"
  end

  # Plays every script through both engines and returns one divergence per
  # script that has one. `first` may be nil, in which case the golden files in
  # `goldens` stand in for it.
  def self.diff(second, first: nil, scripts: EngineSweep.scripts, goldens: DIRECTORY)
    scripts.filter_map do |script|
      expected = first ? first.play(script) : golden(script, goldens)
      first_divergence(script, expected, second.play(script))
    end
  end

  def self.golden(script, directory = DIRECTORY)
    path = Rails.root.join(directory, "#{script.name}.json")
    raise EngineSweep::InvalidScript, "#{script.name}: no golden file at #{directory}/ -- see docs/engine-parity.md" unless path.exist?

    JSON.parse(path.read).fetch("steps").map { |row| row.fetch("dump") }
  end
end
