# WHETHER THE BUILT ENGINE EXTENSION IS THE PINNED ONE, decided on the files.
#
# THE BUG IT IS FOR. The owner's `ext/renderedstep/build/renderedstep_native.so`
# was built one morning, and the pin in `ext/renderedstep/Cargo.toml` moved to a
# newer engine commit later. He pulled by hand, so `bin/update` had no range to
# see the crate move in, and its other question -- "is there a built one at all?"
# -- said yes. The old extension stayed, and `backfill_items` failed with
# "location/kind: the engine's data has no such file": the new Ruby asked the old
# engine for a file only the new engine has.
#
# So `bin/rails engine:build` writes a STAMP beside the library saying what it
# was built from -- the pinned engine commit, and digests of `Cargo.lock` and of
# the crate's own sources -- and the question is asked of the stamp instead of
# of a range: does it say what the checkout says now? A missing stamp is stale,
# since nothing says what that library was built from; so is a build against a
# local engine (`ENGINE_SOURCE`), which is not the pin.
#
# THIS IS THE DECISION AND NOT THE ACT, a pure function over the stamp's text
# and the checkout's, so it is asserted without a toolchain
# (`Update::EngineStampTest`). `bin/update` reads it to decide on a rebuild and
# `EngineData` reads it to say why an engine-owned file is missing.
#
# PLAIN RUBY, no Rails: `bin/update` and `engine:build` read this by `require`
# without booting the app. Nothing in here may reach for a Rails constant.
require "digest"

module Update
  class EngineStamp
    CRATE = File.expand_path("../../ext/renderedstep", __dir__)
    # Beside the library, so it is ignored with it (`/ext/renderedstep/build`).
    FILE = "build/renderedstep_native.stamp".freeze
    LIBRARY_GLOB = "build/renderedstep_native.*".freeze

    # What a stale extension looks like to somebody reading an error.
    ADVICE = "the engine extension is older than the pinned engine; run bin/rails engine:build".freeze

    Decision = Data.define(:stale, :reason) do
      def stale? = stale
    end

    # What `ADVICE` is true of: a library built, but not from the pin. An
    # extension that is not built at all says so in its own words.
    def self.outdated?(crate = CRATE)
      Dir[File.join(crate, LIBRARY_GLOB)].any? { |path| path != File.join(crate, FILE) } && check(crate).stale?
    end

    # What the checkout at `crate` would build: the pinned engine commit, the
    # lockfile's digest and the crate sources' digest, as a stamp's fields.
    def self.expected(crate = CRATE)
      {
        "rev" => pinned_rev(File.read(File.join(crate, "Cargo.toml"))),
        "lock" => Digest::SHA256.file(File.join(crate, "Cargo.lock")).hexdigest,
        "crate" => crate_digest(crate)
      }
    end

    # `source:` is a local engine checkout the build used instead of the pin.
    def self.write!(crate = CRATE, source: nil)
      fields = expected(crate)
      fields["rev"] = "local #{source}" if source
      File.write(File.join(crate, FILE), fields.map { |key, value| "#{key}: #{value}\n" }.join)
    end

    # The decision for the checkout at `crate` as it stands on disk.
    def self.check(crate = CRATE)
      stamp = File.join(crate, FILE)
      decide(built: Dir[File.join(crate, LIBRARY_GLOB)].any? { |path| path != stamp },
             stamp: File.file?(stamp) ? File.read(stamp) : nil,
             expected: expected(crate))
    end

    # `stamp` is the stamp file's text, or nil when there is none.
    def self.decide(built:, stamp:, expected:)
      return Decision.new(stale: true, reason: "the extension is not built yet.") unless built
      if stamp.nil?
        return Decision.new(stale: true, reason: "the extension has no build stamp, so nothing says it is the pinned engine.")
      end

      recorded = parse(stamp)
      if recorded["rev"] != expected["rev"]
        Decision.new(stale: true, reason: "the extension was built from engine #{short(recorded["rev"])}; " \
                                          "the pin is #{short(expected["rev"])}.")
      elsif recorded["lock"] != expected["lock"]
        Decision.new(stale: true, reason: "the extension was built against another Cargo.lock.")
      elsif recorded["crate"] != expected["crate"]
        Decision.new(stale: true, reason: "the extension's crate sources changed since it was built.")
      else
        Decision.new(stale: false, reason: "built from the pinned engine #{short(expected["rev"])}.")
      end
    end

    def self.pinned_rev(cargo_toml)
      cargo_toml[/renderedstep-engine = \{ git = "[^"]+", rev = "(\h{40})" \}/, 1]
    end

    # Cargo.toml and every file under src/ and .cargo/, by path and content.
    def self.crate_digest(crate)
      files = [ "Cargo.toml" ] + Dir.glob("{src,.cargo}/**/*", File::FNM_DOTMATCH, base: crate)
                                    .select { |path| File.file?(File.join(crate, path)) }.sort
      Digest::SHA256.hexdigest(files.map { |path| "#{path}\0#{Digest::SHA256.file(File.join(crate, path)).hexdigest}\n" }.join)
    end

    def self.parse(text)
      text.to_s.lines.filter_map { |line| line.strip.split(": ", 2) if line.include?(": ") }.to_h
    end

    def self.short(rev)
      return "unknown" if rev.nil? || rev.empty?

      rev.match?(/\A\h{40}\z/) ? rev[0, 7] : rev
    end

    private_class_method :parse, :short
  end
end
