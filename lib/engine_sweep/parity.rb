# THE SAME SCRIPT PLAYED THROUGH TWO ENGINES, compared step by step.
#
# A sweep script says what should happen; `EngineSweep::Dump` says what did,
# whole. This plays a script through an ENGINE -- anything that answers
# `#play(script)` with one dump per step, in the script's order -- and either
# writes the dumps down as golden files or compares two engines' and names the
# first step where they part. docs/engine-parity.md is the contract an engine
# other than this one implements.
#
# `Ruby` is the engine the rest of the app is: `EngineSweep::Walk` with a
# listener, so it plays exactly the way `rake game:sweep` plays, in the same
# rolled-back transaction with the same pinned ids. `Command` is any other
# engine behind a subprocess: it is handed a script's path and prints one
# dump per line.
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

    def initialize(command)
      @command = command
      @name = command
    end

    def play(script)
      environment = WITHHELD.to_h { |key| [ key, nil ] }
      output, status = Open3.capture2(environment, *Shellwords.split(@command), script.path.to_s)
      raise EngineSweep::InvalidScript, "#{@command} failed on #{script.name} (#{status})" unless status.success?

      output.lines.map(&:strip).reject(&:empty?).map { |line| JSON.parse(line) }
    end
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
  def self.files(engine = Ruby.new, scripts = EngineSweep.scripts)
    scripts.to_h { |script| [ "#{script.name}.json", render(document(script, engine.play(script))) ] }
  end

  def self.write!(engine = Ruby.new, scripts = EngineSweep.scripts)
    directory = Rails.root.join(DIRECTORY)
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
  # script that has one. `first` may be nil, in which case the committed
  # golden files stand in for it.
  def self.diff(second, first: nil, scripts: EngineSweep.scripts)
    scripts.filter_map do |script|
      expected = first ? first.play(script) : golden(script)
      first_divergence(script, expected, second.play(script))
    end
  end

  def self.golden(script)
    path = Rails.root.join(DIRECTORY, "#{script.name}.json")
    raise EngineSweep::InvalidScript, "#{script.name}: no golden file at #{DIRECTORY}/ -- run bin/rails engine:parity" unless path.exist?

    JSON.parse(path.read).fetch("steps").map { |row| row.fetch("dump") }
  end
end
