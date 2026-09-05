# WHETHER A PULL HAS TO RE-SEED, decided on the range and nothing else.
#
# THE BUG IT IS FOR. A world here outlives its seed FILE the way it outlives its
# schema. The captain seeded The Salt Assizes one evening; the next morning a PR
# gave the protagonist's tide-slate `readable: true` and an inscription in
# `db/seeds/worlds/the-salt-assizes.yml`. Nothing he ran after pulling ever
# looked at a seed file again -- `bin/update` ran migrations and the
# `Update::REGISTRY` steps -- so the world's own row stayed blank, every
# playthrough had already copied that blank row, and `read slate` was correctly
# refused with "there is nothing written on it" for days.
#
# So `bin/update` asks the same question about `db/seeds/worlds` that it already
# asks about `Gemfile.lock`: did anything under it move between the commit I was
# on and the one I pulled? The answer is a range diff, which is cheap, exact and
# silent when nothing moved.
#
# THIS IS THE DECISION AND NOT THE ACT. It is a pure function over git's answer
# so it can be asserted without a checkout, a network or a database
# (`Update::SeedFilesTest`); `rake game:reseed` is the act, and
# `WorldSeed::Loader` is what that runs.
#
# IT IS NOT AN `Update::REGISTRY` STEP, deliberately. A step must be idempotent,
# quiet and offline, and a re-seed is all three -- but a step runs on EVERY
# `bin/update`, and re-asserting three world files over a played database on
# every pull is not what the registry is for. The range is what makes this
# proportionate, and the registry has no range.
#
# PLAIN RUBY, no Rails: `bin/update` is a script that has not booted the app and
# reads this by `require`. Nothing in here may reach for a Rails constant.
module Update
  class SeedFiles
    # The path git is asked about, relative to the repository root.
    DIRECTORY = "db/seeds/worlds".freeze

    # What to do, why, and about which files. `files` is empty for a forced
    # re-seed: `--seed` has no range to name.
    Decision = Data.define(:reseed, :files, :reason) do
      def reseed? = reseed

      # What `--dry-run` prints. It names the files rather than rehearsing the
      # load: `WorldSeed::Loader` has no dry mode and a half-load is worse than
      # no answer, so this says what WOULD run and writes nothing.
      def dry_line
        "would reseed: #{files.empty? ? "every checked-in world file" : files.join(", ")}"
      end
    end

    # `range:` is whether there is an OLD..TARGET to read at all -- `--skip-pull`
    # has none, and a checkout already up to date has an empty one, which is a
    # real answer rather than an absent one.
    def self.decide(changed: [], forced: false, range: true)
      files = Array(changed).map(&:strip).reject(&:empty?)

      if forced
        Decision.new(reseed: true, files: [],
                     reason: "--seed: re-asserting every checked-in world file over this database.")
      elsif !range
        Decision.new(reseed: false, files: [],
                     reason: "no range to read, so nothing is claimed about the seed files. `--seed` forces a re-seed.")
      elsif files.empty?
        Decision.new(reseed: false, files: [], reason: "no world file moved in that range.")
      else
        Decision.new(reseed: true, files: files,
                     reason: "#{files.size} world file#{"s" unless files.one?} moved in that range.")
      end
    end

    # `git diff --name-only` output as a list of paths.
    def self.changed_paths(output)
      output.to_s.lines.map(&:strip).reject(&:empty?)
    end
  end
end
