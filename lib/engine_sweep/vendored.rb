# WHAT THIS REPOSITORY COPIES FROM THE RUST ENGINE, held byte for byte to the
# commit the extension is pinned to (`ext/renderedstep/Cargo.toml`).
#
# The engine owns behaviour: an engine change that moves a rule rewrites the
# goldens with its own parity binary and blesses the vector portions that are
# its own, as a reviewed diff in the engine's repository. This repository
# vendors those files at the pin, and `bin/rails engine:vendored` fails when
# a copy here is not exactly the pinned commit's:
#
# - every golden (`test/engine_parity/<script>.json`) against the engine's
#   `parity/goldens/`, the two sets of names included;
# - every sweep script (`lib/engine_sweep/scripts/`), less its comments and
#   `why:` notes, against the engine's `parity/scripts/`, so a golden is a
#   golden of the script it is named after;
# - every portion the engine owns (`EngineVectors::ENGINE_OWNED`, which must
#   be the engine's `vectors/ENGINE_OWNED`) against its `vectors/`.
#
# THE PINNED SOURCE IS THE ONE CARGO FETCHED to build the extension, found
# with `cargo metadata`, so no second clone is made. `ENGINE_SOURCE=<checkout>`
# checks against a local copy of the engine instead, as `engine:build` builds
# against one.
module EngineSweep::Vendored
  CRATE = "ext/renderedstep".freeze
  PACKAGE = "renderedstep-engine".freeze

  class Unavailable < StandardError; end

  def self.pin
    Rails.root.join(CRATE, "Cargo.toml").read[/#{PACKAGE} = \{ git = "[^"]+", rev = "(\h{40})" \}/o, 1] or
      raise Unavailable, "#{CRATE}/Cargo.toml pins no engine commit"
  end

  def self.source
    return Pathname(ENV["ENGINE_SOURCE"]).expand_path if ENV["ENGINE_SOURCE"].present?

    output, status = Open3.capture2("cargo", "metadata", "--format-version", "1", "--locked",
                                    chdir: Rails.root.join(CRATE).to_s)
    raise Unavailable, "cargo metadata failed in #{CRATE} (#{status})" unless status.success?

    package = JSON.parse(output).fetch("packages").find { |candidate| candidate["name"] == PACKAGE }
    unless package && package["source"].to_s.end_with?("##{pin}")
      raise Unavailable, "cargo resolved #{PACKAGE} to #{package&.dig("source").inspect}, not the pinned #{pin}"
    end

    Pathname(package.fetch("manifest_path")).dirname
  end

  # One sentence per file that is not the engine's, or is on one side only.
  def self.problems(source = self.source)
    goldens(source) + scripts(source) + vectors(source)
  rescue Errno::ENOENT => e
    missing = Pathname(e.message[/ - (.*)\z/, 1].to_s)
    [ "the engine source at #{source} has no #{missing.absolute? ? missing.relative_path_from(source) : missing}" ]
  end

  def self.goldens(source = self.source)
    here = Rails.root.join(EngineSweep::Parity::DIRECTORY)
    compared("golden", source.join("parity/goldens"), here, names(here, "*.json").reject { |name| name.end_with?(".checks.json") })
  end

  def self.scripts(source = self.source)
    there = source.join("parity/scripts")
    ours = EngineSweep.scripts.to_h { |script| [ "#{script.name}.yml", stripped(script.path) ] }
    theirs = names(there, "*.yml")
    (ours.keys | theirs).sort.filter_map do |name|
      next "script #{name} is not in the engine's parity/scripts" unless theirs.include?(name)
      next "script #{name} is in the engine's parity/scripts and not here" unless ours.key?(name)

      "script #{name} differs from the engine's parity/scripts/#{name}" unless there.join(name).read == ours.fetch(name)
    end
  end

  def self.vectors(source = self.source)
    listed = source.join("vectors/ENGINE_OWNED").read.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
    here = Rails.root.join(EngineVectors::DIRECTORY)
    owned = EngineVectors::ENGINE_OWNED.map { |portion| "#{portion}.json" }
    problems = listed.sort == EngineVectors::ENGINE_OWNED.sort ? [] : [ "the engine owns #{listed.inspect}, and EngineVectors::ENGINE_OWNED says #{EngineVectors::ENGINE_OWNED.inspect}" ]
    problems + compared("vector portion", source.join("vectors"), here, owned, both: false)
  end

  # How the engine stores a script: re-emitted by Ruby's YAML library with the
  # comments and the `why:` notes, which no engine reads, taken out.
  def self.stripped(path)
    document = YAML.safe_load_file(path)
    document.delete("why")
    document.fetch("steps").each { |step| step.delete("why") }
    YAML.dump(document)
  end

  def self.names(directory, pattern) = Dir.glob(directory.join(pattern)).map { |path| File.basename(path) }.sort

  # `names` in `here` against the same names in `there`; with `both`, a file
  # `there` has that `here` does not is a problem too.
  def self.compared(what, there, here, ours, both: true)
    theirs = both ? names(there, "*.json") : ours
    (ours | theirs).sort.filter_map do |name|
      next "#{what} #{name} is not in the engine's #{there.basename}" unless there.join(name).exist?
      next "#{what} #{name} is in the engine's #{there.basename} and not here" unless ours.include?(name)

      "#{what} #{name} differs from the engine's #{there.basename}/#{name}" unless there.join(name).binread == here.join(name).binread
    end
  end
end
