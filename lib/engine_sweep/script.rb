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
class EngineSweep::Script
  # Whose game a step with no `player` is typed into.
  DEFAULT_PLAYER = "first"

  Step = Data.define(:index, :id, :typed, :why, :player, :expectation) do
    # How a step is named when it fails. The number is always there because a
    # script may type the same line twice on purpose.
    def label = "step #{index}#{" #{id}" if id.present?}#{" (#{player})" unless player == DEFAULT_PLAYER}"
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

      unknown = row.keys - %w[id type why player expect]
      raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} has unknown key(s) #{unknown.inspect}" if unknown.any?

      Step.new(index: offset + 1, id: row["id"], typed: fetch!(row, "type", path), why: row["why"],
               player: row["player"].presence || DEFAULT_PLAYER,
               expectation: EngineSweep::Expectation.read(row["expect"], "#{path}: step #{offset + 1}"))
    end
  end

  private_class_method :fetch!, :read_steps

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
