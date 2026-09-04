# ONE STORED WALK: which world, what gets typed, and what the records should
# say afterwards.
#
# IT IS A FIXTURE, NOT A LANGUAGE. There is no branching, no variables and no
# way to compute anything -- a step is a line somebody could have typed and a
# block of facts somebody could have read off the screen. Everything a script
# can assert is in `Expectation::KEYS` and a key outside that list raises, so a
# typo cannot turn into an expectation that silently holds.
#
# THE SHAPE:
#
#   story: The Salt Assizes          # a seeded world, by title
#   steps:
#   - type: drop the tide-slate      # what the player typed
#     expect:
#       changed: true
#       location: The Causeway Court (realized)
#       here: [Assize tide-slate]
#       carrying: []
#
# `id` and `why` are optional on a step: the first names it in a failure, the
# second says what the step is for. Neither is asserted.
#
# `player` IS THE ONE THING THAT IS NOT ONE LINE SOMEBODY TYPED, and it exists
# because the defect it regression-tests needs two people playing one world:
# the party's inventory belongs to the playthrough, so a script has to be able
# to type into a second one and read back what IT is holding. A step with no
# `player` goes to the default, so every existing script is one playthrough and
# unchanged.
#
#   - type: take the ward stamp   # the default player
#   - type: look
#     player: second              # a second playthrough of the same world
#     expect:
#       carrying: [Ward Office 12 daybook]
#
# `reseed: true` IS THE OTHER THING THAT IS NOT ONE LINE SOMEBODY TYPED, and it
# is here for the same kind of reason: re-seeding a world somebody is PLAYING is
# a thing the captain does daily and nothing walked it. A step with it re-loads
# the world file over the copy this walk has been playing -- the same
# `WorldSeed::Loader` call `bin/rails db:seed` makes -- and then reads the
# records back with nothing else having happened, so every expectation below it
# is a statement about what a re-seed did or did not disturb. What the loader
# reconciled and what it warned about are in the step's `note`, so a script can
# pin the reconciliation itself and not just its effect.
#
#   - type: take the ward stamp
#   - reseed: true
#     expect:
#       carrying: []              # the file put the stamp back on the floor
#       here: [ward stamp]
#
# A step carries `type` or `reseed`, never both and never neither.
#
# `reseed:` MAY NAME A DIFFERENT VERSION OF THE FILE, which is what lets the
# walk reach the defect rather than only the rule. A rename is what the SECOND
# version of a seed file says, and before `WorldSeed.natural_key` a renamed room
# was a room that did not exist yet -- so re-seeding created a second one beside
# the first and the office opened onto both. A mapping says which names this
# load writes, and nothing else about the file changes:
#
#   - reseed:
#       locations: { The Supply Closet: Supply Closet }
#       items: { ward stamp: Ward Stamp }
#
# It is still a fixture rather than a language: the mapping says which version
# of the file is being loaded, the way `story:` says which file. The invariants
# after the walk are then checked against the file AS LAST LOADED, so a rename
# does not read as an invented doorway.
class EngineSweep::Script
  # Whose game a step with no `player` is typed into.
  DEFAULT_PLAYER = "first"

  Step = Data.define(:index, :id, :typed, :why, :player, :reseed, :expectation) do
    # How a step is named when it fails. The number is always there because a
    # script may type the same line twice on purpose.
    def label = "step #{index}#{" #{id}" if id.present?}#{" (#{player})" unless player == DEFAULT_PLAYER}"

    def reseed? = !reseed.nil?

    # `{ "locations" => {...}, "items" => {...} }`, and empty for a plain
    # `reseed: true` -- the same file loaded again.
    def renames = reseed.is_a?(Hash) ? reseed : {}
  end

  attr_reader :path, :story, :steps, :why

  def self.load(path)
    document = YAML.safe_load_file(path)
    raise EngineSweep::InvalidScript, "#{path}: expected a mapping" unless document.is_a?(Hash)

    new(path: path,
        story: fetch!(document, "story", path),
        why: document["why"],
        steps: read_steps(fetch!(document, "steps", path), path))
  rescue Psych::Exception => e
    raise EngineSweep::InvalidScript, "#{path}: #{e.message}"
  end

  def self.fetch!(document, key, path)
    document.fetch(key) { raise EngineSweep::InvalidScript, "#{path}: no #{key.inspect}" }
  end

  def self.read_steps(rows, path)
    raise EngineSweep::InvalidScript, "#{path}: \"steps\" is not a list" unless rows.is_a?(Array)

    rows.each_with_index.map do |row, offset|
      raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} is not a mapping" unless row.is_a?(Hash)

      unknown = row.keys - %w[id type why player reseed expect]
      raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} has unknown key(s) #{unknown.inspect}" if unknown.any?

      reseed = read_reseed(row["reseed"], "#{path}: step #{offset + 1}") if row.key?("reseed")

      if reseed && row.key?("type")
        raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} is both a typed line and a `reseed`, and it can only be one"
      end
      unless reseed || row.key?("type")
        raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} has no \"type\" and is not a `reseed`"
      end

      Step.new(index: offset + 1, id: row["id"], typed: row["type"], why: row["why"],
               player: row["player"].presence || DEFAULT_PLAYER, reseed: reseed,
               expectation: EngineSweep::Expectation.read(row["expect"], "#{path}: step #{offset + 1}"))
    end
  end

  # `true` for the same file again, or a mapping of what this load renames.
  # Closed, like `Expectation::KEYS`: a misspelt `location:` here would read as
  # a plain re-seed and the step would assert the wrong thing quietly.
  RENAMEABLE = %w[locations items].freeze

  def self.read_reseed(value, where)
    return true if value == true
    raise EngineSweep::InvalidScript, "#{where}: \"reseed\" is `true` or a mapping of #{RENAMEABLE.join(" / ")}, got #{value.inspect}" unless value.is_a?(Hash)

    unknown = value.keys - RENAMEABLE
    raise EngineSweep::InvalidScript, "#{where}: \"reseed\" has unknown key(s) #{unknown.inspect}. There is: #{RENAMEABLE.join(", ")}" if unknown.any?

    value.each_value do |mapping|
      raise EngineSweep::InvalidScript, "#{where}: a \"reseed\" rename is a mapping of old name to new name, got #{mapping.inspect}" unless mapping.is_a?(Hash)
    end

    value
  end

  private_class_method :fetch!, :read_steps, :read_reseed

  def initialize(path:, story:, steps:, why: nil)
    @path = path
    @story = story
    @steps = steps
    @why = why
  end

  # The name a report calls it by: the filename without its extension, which is
  # what somebody would type to open it.
  def name = File.basename(path, ".yml")

  # Every game this script is typed into, in the order it first reaches them.
  # One for almost every script; the point of naming them is that a second one
  # is possible at all.
  def players = steps.map(&:player).uniq

  # The checked-in world file this script walks. Named from the title rather
  # than from the script's own filename, so several scripts can walk one world.
  def seed_file = WorldSeed::DIRECTORY.join("#{WorldSeed.slug(story)}.yml")
end
